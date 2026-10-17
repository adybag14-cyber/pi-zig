//! get-tsconfig 4.14.0 paths-matcher and pattern helpers.
const h = @import("native_tsconfig_values.zig");
const c = h.c;
const Scope = h.Scope;
fn assertStar(s: *Scope, state: c.JSValue, value: c.JSValue, message: c.JSValue) !void {
    const matches = try s.invoke(value, "match", &.{try s.get(state, "starPattern")});
    if (s.truthy(matches) and try h.length(s, matches) > 1) return h.throw(s, "Error", message);
}
fn parsePattern(s: *Scope, pattern: c.JSValue) !c.JSValue {
    if (!s.truthy(try s.invoke(pattern, "includes", &.{try s.text("*")}))) return pattern;
    const split = try s.invoke(pattern, "split", &.{try s.text("*")});
    const result = try s.object(); try s.put(result, "prefix", try h.at(s, split, 0)); try s.put(result, "suffix", try h.at(s, split, 1)); return result;
}
fn substitution(engine: *h.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const value = h.arg(args, 0); const pattern = roots[1];
    const message = try s.concat(try s.concat(try s.concat(try s.concat(try s.text("Substitution '"), try s.stringify(value)), try s.text("' in pattern '")), try s.stringify(pattern)), try s.text("' can have at most one '*' character."));
    try assertStar(&s, roots[0], value, message);
    if (!s.truthy(roots[2]) and !try h.relative(&s, roots[0], value) and !s.truthy(try h.path(&s, roots[0], "isAbsolute", &.{value}))) return h.throw(&s, "Error", try s.text("Non-relative paths are not allowed when 'baseUrl' is not set. Did you forget a leading './'?"));
    return c.JS_DupValue(engine.context, try h.path(&s, roots[0], "resolve", &.{ roots[3], value }));
}
fn entryCallback(engine: *h.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const pair = h.arg(args, 0);
    const pattern = try h.at(&s, pair, 0); const substitutions = try h.at(&s, pair, 1);
    const message = try s.concat(try s.concat(try s.text("Pattern '"), try s.stringify(pattern)), try s.text("' can have at most one '*' character."));
    try assertStar(&s, roots[0], pattern, message);
    const result = try s.object(); try s.put(result, "pattern", try parsePattern(&s, pattern));
    const method = try s.get(substitutions, "map");
    const callback = try s.own(try h.functions.createArrow(engine, "", 1, h.Boundary(substitution).invoke, &.{ roots[0], pattern, roots[1], roots[2] }));
    try s.put(result, "substitutions", try s.call(method, substitutions, &.{callback})); return c.JS_DupValue(engine.context, result);
}
fn replace(engine: *h.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return c.JS_DupValue(engine.context, try h.slash(&s, try s.invoke(h.arg(args, 0), "replace", &.{ try s.text("*"), roots[0] })));
}
fn match(engine: *h.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const state = roots[0]; const specifier = h.arg(args, 0);
    if (try h.relative(&s, state, specifier)) return h.v.js.array(engine);
    const entries = roots[1]; const count = try h.length(&s, entries);
    const patterns = try s.array(); var best = c.pi_js_undefined(); var best_length: i64 = -1; var steps: usize = 0;
    for (0..count) |index| {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); try h.tick(engine, &steps);
        const entry = try h.at(&row, entries, @intCast(index)); const pattern = try row.get(entry, "pattern");
        if (row.equal(pattern, specifier)) {
            return h.v.js.invoke(engine, try row.get(entry, "substitutions"), "map", &.{try row.get(state, "slashFunction")});
        }
        if (c.JS_IsString(pattern)) continue;
        try h.push(&row, patterns, entry);
    }
    for (0..try h.length(&s, patterns)) |index| {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); try h.tick(engine, &steps);
        const entry = try h.at(&row, patterns, @intCast(index)); const pattern = try row.get(entry, "pattern");
        const prefix = try row.get(pattern, "prefix"); const suffix = try row.get(pattern, "suffix");
        if (!row.truthy(try row.invoke(specifier, "startsWith", &.{prefix})) or !row.truthy(try row.invoke(specifier, "endsWith", &.{suffix}))) continue;
        const size = try h.length(&row, prefix);
        if (@as(i64, size) > best_length) { best = try s.own(c.JS_DupValue(engine.context, entry)); best_length = size; }
    }
    const output = try s.array();
    if (c.JS_IsUndefined(best)) {
        if (s.truthy(roots[2])) try h.push(&s, output, try h.slash(&s, try h.path(&s, state, "join", &.{ roots[3], specifier })));
        return c.JS_DupValue(engine.context, output);
    }
    const pattern = try s.get(best, "pattern");
    const slice = try s.get(specifier, "slice");
    const begin = try s.get(try s.get(pattern, "prefix"), "length");
    const end = try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try s.get(specifier, "length"), try s.get(try s.get(pattern, "suffix"), "length"))));
    const matched = try s.call(slice, specifier, &.{ begin, end });
    const substitutions = try s.get(best, "substitutions"); const method = try s.get(substitutions, "map");
    const callback = try s.own(try h.functions.createArrow(engine, "", 1, h.Boundary(replace).invoke, &.{matched}));
    return h.v.js.call(engine, method, substitutions, &.{callback});
}
pub fn create(engine: *h.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const state = roots[0];
    const result = h.arg(args, 0); const options = try s.get(try s.get(result, "config"), "compilerOptions");
    if (!s.truthy(options)) return c.pi_js_null();
    const base = try s.get(options, "baseUrl"); const paths = try s.get(options, "paths");
    if (!s.truthy(base) and !s.truthy(paths)) return c.pi_js_null();
    const implicit_symbol = try s.get(state, "implicitBaseUrl");
    const implicit = if (try h.v.js.hasKey(engine, options, implicit_symbol)) try h.key(&s, options, implicit_symbol) else c.pi_js_bool(engine.context, 0);
    const directory = try h.path(&s, state, "dirname", &.{try s.get(result, "path")});
    const resolved = try h.path(&s, state, "resolve", &.{ directory, if (s.truthy(base)) base else if (s.truthy(implicit)) implicit else try s.text(".") });
    var entries = try s.array();
    if (s.truthy(paths)) {
        const pairs = try s.invoke(try s.global("Object"), "entries", &.{paths});
        const method = try s.get(pairs, "map");
        const callback = try s.own(try h.functions.createArrow(engine, "", 1, h.Boundary(entryCallback).invoke, &.{ state, base, resolved }));
        entries = try s.call(method, pairs, &.{callback});
    }
    return h.functions.createArrow(engine, "", 1, h.Boundary(match).invoke, &.{ state, entries, base, resolved });
}
