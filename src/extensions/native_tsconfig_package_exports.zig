//! resolve-pkg-maps 1.0.0 resolveExports, consumed by config package extends.
//! Original MIT source and archive are retained in the authority packet.
const h = @import("native_tsconfig_values.zig");
const c = h.c;
const Scope = h.Scope;
fn keys(s: *Scope, value: c.JSValue) !c.JSValue { return s.invoke(try s.global("Object"), "keys", &.{value}); }
fn regexTest(s: *Scope, state: c.JSValue, field: [*:0]const u8, value: c.JSValue) !bool { return s.truthy(try s.invoke(try s.get(state, field), "test", &.{value})); }
fn target(engine: *h.v.em.Engine, state: c.JSValue, value: c.JSValue, replacement: c.JSValue, depth: usize) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (depth > 128) return h.quota(&s, "Native tsconfig package exports nesting quota exceeded");
    const result = try s.array(); if (h.v.nullish(value)) return c.JS_DupValue(engine.context, result);
    if (c.JS_IsString(value)) {
        const segments = try s.invoke(value, "split", &.{try s.get(state, "packageSeparators")});
        if (try h.eq(&s, try h.at(&s, segments, 0), "..")) return error.InvalidTsconfigPackageTarget;
        for (1..try h.length(&s, segments)) |i| if (try regexTest(&s, state, "badPackageSegment", try h.at(&s, segments, @intCast(i)))) return error.InvalidTsconfigPackageTarget;
        const resolved = if (s.truthy(replacement)) try s.invoke(value, "replace", &.{ try s.get(state, "packageStars"), replacement }) else value;
        try h.push(&s, result, resolved); return c.JS_DupValue(engine.context, result);
    }
    if (try h.v.array(&s, value)) {
        for (0..try h.length(&s, value)) |i| {
            var row: Scope = .{ .engine = engine }; defer row.deinit();
            const values = try row.own(try target(engine, state, try h.at(&row, value, @intCast(i)), replacement, depth + 1));
            for (0..try h.length(&row, values)) |j| try h.push(&row, result, try h.at(&row, values, @intCast(j)));
        }
        return c.JS_DupValue(engine.context, result);
    }
    if (c.JS_IsObject(value)) {
        const names = try keys(&s, value);
        for (0..try h.length(&s, names)) |i| {
            var row: Scope = .{ .engine = engine }; defer row.deinit(); const name = try h.at(&row, names, @intCast(i));
            if (try regexTest(&row, state, "numericPackageKey", name)) return error.InvalidTsconfigPackageConfig;
            if (try h.eq(&row, name, "default") or try h.eq(&row, name, "require") or try h.eq(&row, name, "types")) return target(engine, state, try h.key(&row, value, name), replacement, depth + 1);
        }
        return c.JS_DupValue(engine.context, result);
    }
    return error.InvalidTsconfigPackageTarget;
}
fn position(s: *Scope, value: c.JSValue) !i64 {
    var index: i64 = 0; if (c.JS_ToInt64(s.engine.context, &index, try s.invoke(value, "indexOf", &.{try s.text("*")})) < 0) return h.v.js.capture(s.engine); return index;
}
pub fn resolve(engine: *h.v.em.Engine, state: c.JSValue, exports: c.JSValue, subpath: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const requested = if (try h.eq(&s, subpath, "")) try s.text(".") else try s.concat(try s.text("./"), try s.stringify(subpath));
    var mapping = exports; var conditions = false;
    if (c.JS_IsObject(mapping) and !try h.v.array(&s, mapping)) {
        const names = try keys(&s, mapping); var kind: ?bool = null;
        for (0..try h.length(&s, names)) |i| {
            const name = try h.at(&s, names, @intCast(i)); const condition = try h.eq(&s, name, "") or !try h.starts(&s, name, ".");
            if (kind) |old| { if (old != condition) return error.InvalidTsconfigPackageConfig; } else kind = condition;
        }
        conditions = kind orelse false;
    }
    if (c.JS_IsString(mapping) or try h.v.array(&s, mapping) or conditions) {
        const wrapped = try s.object(); try s.put(wrapped, ".", mapping); mapping = wrapped;
    }
    var selected = c.pi_js_undefined(); var replacement = c.pi_js_undefined();
    if (!s.truthy(try s.invoke(requested, "includes", &.{try s.text("*")})) and s.truthy(try s.invoke(mapping, "hasOwnProperty", &.{requested}))) selected = requested else {
        const names = try keys(&s, mapping); var steps: usize = 0;
        for (0..try h.length(&s, names)) |i| {
            var row: Scope = .{ .engine = engine }; defer row.deinit(); try h.tick(engine, &steps);
            const name = try h.at(&row, names, @intCast(i)); if (!row.truthy(try row.invoke(name, "includes", &.{try row.text("*")}))) continue;
            const parts = try row.invoke(name, "split", &.{try row.text("*")}); if (!c.JS_IsUndefined(try h.at(&row, parts, 2))) continue;
            const prefix = try h.at(&row, parts, 0); const suffix = try h.at(&row, parts, 1);
            if (!row.truthy(try row.invoke(requested, "startsWith", &.{prefix})) or !row.truthy(try row.invoke(requested, "endsWith", &.{suffix}))) continue;
            const slice = try row.get(requested, "slice"); const begin = try row.get(prefix, "length");
            const suffix_length = try h.length(&row, suffix);
            const middle = try row.call(slice, requested, &.{ begin, if (suffix_length == 0) c.pi_js_undefined() else h.n(&row, -@as(i64, suffix_length)) });
            if (!row.truthy(middle)) continue;
            var prefer = c.JS_IsUndefined(selected);
            if (!prefer) {
                const old_position = try position(&row, selected); const new_position = try position(&row, name);
                prefer = if (old_position == new_position) try h.length(&row, name) > try h.length(&row, selected) else new_position > old_position;
            }
            if (prefer) {
                // Selected names and captures must survive the row's temporary roots.
                selected = try s.own(c.JS_DupValue(engine.context, name)); replacement = try s.own(c.JS_DupValue(engine.context, middle));
            }
        }
    }
    const values = try s.own(try target(engine, state, try h.key(&s, mapping, selected), replacement, 0));
    if (try h.length(&s, values) == 0) return error.TsconfigPackagePathNotExported;
    for (0..try h.length(&s, values)) |i| {
        const value = try h.at(&s, values, @intCast(i));
        if (!try h.starts(&s, value, "./") and !try regexTest(&s, state, "packageScheme", value)) return error.InvalidTsconfigPackageTarget;
    }
    return c.JS_DupValue(engine.context, values);
}
