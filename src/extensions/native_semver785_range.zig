//! Exact strict/default Range/Comparator transformation order from semver7.8.5.
const em = @import("engine.zig");
const Scope = @import("native_semver785_scope.zig").Scope;
const ops = @import("native_semver785_ops.zig");
const functions = @import("native_node_function.zig");
const v = @import("native_semver785_version.zig");
const expand = @import("native_semver785_expand.zig");
const c = em.c;
const Callback = enum { parse_range, parse_comparator, comparator, gte0, has_length, not_null_set, caret, tilde, xrange };
fn regex(scope: *Scope, context: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return scope.get(try scope.get(context, "regex"), name);
}
fn callback(engine: *em.Engine, comptime kind: Callback, context: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var scope: Scope = .{ .engine = host };
            defer scope.deinit();
    errdefer |err| scope.failed(err);
            const input = if (args.len > 0) args[0] else c.pi_js_undefined();
            const result = switch (kind) {
                .parse_range => try parseRange(&scope, roots[0], try scope.invoke(input, "trim", &.{})),
                .parse_comparator => try parseComparator(&scope, roots[0], input),
                .comparator => try comparator(&scope, roots[0], input),
                .gte0 => try scope.invoke(try scope.invoke(input, "trim", &.{}), "replace", &.{ try regex(&scope, roots[0], "GTE0"), try scope.text("") }),
                .has_length => try scope.get(input, "length"),
                .not_null_set => c.pi_js_bool(host.context, @intFromBool(!try nullSet(&scope, try v.index(&scope, input, 0)))),
                .caret, .tilde, .xrange => try replacePart(&scope, roots[0], input, kind),
            };
            return scope.finish(c.JS_DupValue(host.context, result));
        }
    };
    return functions.createArrow(engine, "", 1, Adapter.call, &.{context});
}
fn mapped(scope: *Scope, context: c.JSValue, array: c.JSValue, comptime kind: Callback, method: [*:0]const u8) !c.JSValue {
    const function = try scope.get(array, method);
    const mapper = try scope.own(try callback(scope.engine, kind, context));
    return scope.call(function, array, &.{mapper});
}
fn nullSet(scope: *Scope, comparator_value: c.JSValue) !bool {
    return scope.equal(try scope.get(comparator_value, "value"), try scope.text("<0.0.0-0"));
}
fn any(scope: *Scope, comparator_value: c.JSValue) !bool {
    return scope.equal(try scope.get(comparator_value, "value"), try scope.text(""));
}
pub fn create(scope: *Scope, context: c.JSValue, input: c.JSValue) !c.JSValue {
    const trimmed = try scope.invoke(input, "trim", &.{});
    const raw = try scope.invoke(trimmed, "replace", &.{ try regex(scope, context, "SPACE"), try scope.text(" ") });
    const split = try scope.invoke(raw, "split", &.{try scope.text("||")});
    const parsed = try mapped(scope, context, split, .parse_range, "map");
    var sets = try mapped(scope, context, parsed, .has_length, "filter");
    if (try scope.length(sets) == 0) return v.typeError(scope, &.{ try scope.text("Invalid SemVer Range: "), raw });
    if (try scope.length(sets) > 1) {
        const first = try v.index(scope, sets, 0);
        sets = try mapped(scope, context, sets, .not_null_set, "filter");
        if (try scope.length(sets) == 0) {
            sets = try scope.array();
            try scope.index(sets, 0, first);
        } else if (try scope.length(sets) > 1) {
            for (0..try scope.length(sets)) |position| {
                const set = try v.index(scope, sets, @intCast(position));
                if (try scope.length(set) == 1 and try any(scope, try v.index(scope, set, 0))) {
                    sets = try scope.array();
                    try scope.index(sets, 0, set);
                    break;
                }
            }
        }
    }
    const result = try scope.plain();
    try ops.put(scope, result, "set", sets);
    return result;
}
fn parseRange(scope: *Scope, context: c.JSValue, input: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    var range = try scope.invoke(input, "replace", &.{ try regex(scope, context, "BUILDSTRIP"), try scope.text("") });
    const cache = try scope.get(context, "cache");
    const key = try v.join(scope, &.{ try scope.text("0:"), range });
    const cached = try scope.invoke(cache, "get", &.{key});
    if (!c.JS_IsUndefined(cached)) {
        _ = try scope.invoke(cache, "delete", &.{key});
        _ = try scope.invoke(cache, "set", &.{ key, cached });
        return cached;
    }
    const hyphen = try scope.own(try expand.callback(engine, .hyphen));
    range = try scope.invoke(range, "replace", &.{ try regex(scope, context, "HYPHEN"), hyphen });
    inline for (.{ .{ "COMPARATORTRIM", "$1$2$3" }, .{ "TILDETRIM", "$1~" }, .{ "CARETTRIM", "$1^" } }) |entry| range = try scope.invoke(range, "replace", &.{ try regex(scope, context, entry[0]), try scope.text(entry[1]) });
    const parts = try scope.invoke(range, "split", &.{try scope.text(" ")});
    const expanded = try mapped(scope, context, parts, .parse_comparator, "map");
    const joined = try scope.invoke(expanded, "join", &.{try scope.text(" ")});
    const tokens = try scope.invoke(joined, "split", &.{try regex(scope, context, "SPLIT_SPACE")});
    const range_list = try mapped(scope, context, tokens, .gte0, "map");
    const range_map = try scope.builtin("Map", &.{});
    // Original constructs every comparator before checking for a null set.
    // An invalid later token must not be skipped by an earlier null set.
    const comparators = try mapped(scope, context, range_list, .comparator, "map");
    for (0..try scope.length(comparators)) |position| {
        const comp = try v.index(scope, comparators, @intCast(position));
        if (try nullSet(scope, comp)) {
            const result = try scope.array();
            try scope.index(result, 0, comp);
            return result;
        }
        _ = try scope.invoke(range_map, "set", &.{ try scope.get(comp, "value"), comp });
    }
    const size = try scope.get(range_map, "size");
    if (try scope.compare(.greater, size, c.JS_NewInt32(engine.context, 1)) and scope.truthy(try scope.invoke(range_map, "has", &.{try scope.text("")}))) _ = try scope.invoke(range_map, "delete", &.{try scope.text("")});
    const result = try scope.snapshot(try scope.invoke(range_map, "values", &.{}));
    const deleted = try scope.invoke(cache, "delete", &.{key});
    if (!scope.truthy(deleted)) {
        if (try scope.compare(.greater_equal, try scope.get(cache, "size"), c.JS_NewInt32(engine.context, 1000))) {
            const keys = try scope.invoke(cache, "keys", &.{});
            const first = try scope.invoke(keys, "next", &.{});
            _ = try scope.invoke(cache, "delete", &.{try scope.get(first, "value")});
        }
        _ = try scope.invoke(cache, "set", &.{ key, result });
    }
    return result;
}
fn parseComparator(scope: *Scope, context: c.JSValue, input: c.JSValue) !c.JSValue {
    var comp = try scope.invoke(input, "replace", &.{ try regex(scope, context, "BUILD"), try scope.text("") });
    inline for (.{ Callback.caret, .tilde, .xrange }) |kind| {
        const value = if (kind == .xrange) comp else try scope.invoke(comp, "trim", &.{});
        const parts = try scope.invoke(value, "split", &.{try regex(scope, context, "SPLIT_SPACE")});
        comp = try scope.invoke(try mapped(scope, context, parts, kind, "map"), "join", &.{try scope.text(" ")});
    }
    return scope.invoke(try scope.invoke(comp, "trim", &.{}), "replace", &.{ try regex(scope, context, "STAR"), try scope.text("") });
}
fn replacePart(scope: *Scope, context: c.JSValue, input: c.JSValue, comptime kind: Callback) !c.JSValue {
    const value = if (kind == .xrange) try scope.invoke(input, "trim", &.{}) else input;
    const pattern = try regex(scope, context, switch (kind) { .caret => "CARET", .tilde => "TILDE", .xrange => "XRANGE", else => unreachable });
    const replacement = try scope.own(try expand.callback(scope.engine, switch (kind) { .caret => .caret, .tilde => .tilde, .xrange => .xrange, else => unreachable }));
    return scope.invoke(value, "replace", &.{ pattern, replacement });
}
fn comparator(scope: *Scope, context: c.JSValue, input: c.JSValue) !c.JSValue {
    const trimmed = try scope.invoke(input, "trim", &.{});
    const parts = try scope.invoke(trimmed, "split", &.{try regex(scope, context, "SPLIT_SPACE")});
    const comp = try scope.invoke(parts, "join", &.{try scope.text(" ")});
    const matched = try scope.invoke(comp, "match", &.{try regex(scope, context, "COMPARATOR")});
    if (!scope.truthy(matched)) return v.typeError(scope, &.{ try scope.text("Invalid comparator: "), comp });
    var operator = try v.index(scope, matched, 1);
    if (c.JS_IsUndefined(operator) or scope.equal(operator, try scope.text("="))) operator = try scope.text("");
    const operand = try v.index(scope, matched, 2);
    const version = if (scope.truthy(operand)) try v.create(scope, try scope.get(context, "regex"), operand) else c.pi_js_undefined();
    const result = try scope.plain();
    try ops.put(scope, result, "operator", operator);
    try ops.put(scope, result, "semver", version);
    try ops.put(scope, result, "value", if (c.JS_IsUndefined(version)) try scope.text("") else try v.join(scope, &.{ operator, try scope.get(version, "version") }));
    return result;
}
pub fn formatted(scope: *Scope, range: c.JSValue) !c.JSValue {
    const sets = try scope.get(range, "set");
    var result = try scope.text("");
    for (0..try scope.length(sets)) |position| {
        if (position > 0) result = try v.join(scope, &.{ result, try scope.text("||") });
        const set = try v.index(scope, sets, @intCast(position));
        for (0..try scope.length(set)) |index| {
            if (index > 0) result = try v.join(scope, &.{ result, try scope.text(" ") });
            const comp = try v.index(scope, set, @intCast(index));
            result = try v.join(scope, &.{ result, try scope.invoke(try scope.get(comp, "value"), "trim", &.{}) });
        }
    }
    return result;
}
pub fn test(scope: *Scope, context: c.JSValue, range: c.JSValue, version: c.JSValue, parsed_version: bool) !bool {
    const sets = try scope.get(range, "set");
    for (0..try scope.length(sets)) |position| {
        const set = try v.index(scope, sets, @intCast(position));
        if (try testSet(scope, context, set, version, parsed_version)) return true;
    }
    return false;
}
fn testSet(scope: *Scope, context: c.JSValue, set: c.JSValue, version: c.JSValue, parsed_version: bool) !bool {
    const shared_regex = try scope.get(context, "regex");
    const count = try scope.length(set);
    for (0..count) |position| {
        const comp = try v.index(scope, set, @intCast(position));
        const target = try scope.get(comp, "semver");
        if (c.JS_IsUndefined(target)) continue;
        // Comparator.ANY accepts non-string values without construction; a
        // concrete comparator delegates through SemVer's constructor as Source.
        const candidate = if (parsed_version) version else try v.create(scope, shared_regex, version);
        const compared = try v.compare(scope, shared_regex, candidate, target);
        const operator = try scope.get(comp, "operator");
        const accepted = if (scope.equal(operator, try scope.text(""))) compared == 0 else if (scope.equal(operator, try scope.text(">"))) compared > 0 else if (scope.equal(operator, try scope.text(">="))) compared >= 0 else if (scope.equal(operator, try scope.text("<"))) compared < 0 else if (scope.equal(operator, try scope.text("<="))) compared <= 0 else false;
        if (!accepted) return false;
    }
    if (try scope.length(try scope.get(version, "prerelease")) > 0) {
        for (0..count) |position| {
            const comp = try v.index(scope, set, @intCast(position));
            const target = try scope.get(comp, "semver");
            if (c.JS_IsUndefined(target) or try scope.length(try scope.get(target, "prerelease")) == 0) continue;
            if (scope.equal(try scope.get(target, "major"), try scope.get(version, "major")) and scope.equal(try scope.get(target, "minor"), try scope.get(version, "minor")) and scope.equal(try scope.get(target, "patch"), try scope.get(version, "patch"))) return true;
        }
        return false;
    }
    return true;
}
