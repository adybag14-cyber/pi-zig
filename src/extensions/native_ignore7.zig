//! Native ignore 7.0.8 factory for actual PackageManager discovery.
//! No host glob approximation and no embedded JavaScript implementation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const rx = @import("native_ignore7_regex.zig");
const Scope = v.Scope;
const c = v.c;
const Method = enum { add, addPattern, ignores, test_path, checkIgnore, createFilter, filter, filter_path, add_one, valid, setup_windows, init_cache, test_internal, t_internal, manager_add, manager_test, rule_regex, rule_check_regex, rule_make, rule_basename };
fn boolean(scope: *Scope, value: bool) c.JSValue { return c.pi_js_bool(scope.engine.context, @intFromBool(value)); }
fn input(args: []const c.JSValue, at: usize) c.JSValue { return if (at < args.len) args[at] else c.pi_js_undefined(); }
fn function(scope: *Scope, kind: Method, name: [*:0]const u8, length: c_int, roots: []const c.JSValue, arrow: bool) !c.JSValue {
    const Adapter = struct {
        fn callback(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
            return dispatch(engine, receiver, args, data);
        }
    };
    const retained = try scope.engine.gpa.alloc(c.JSValue, roots.len + 1);
    defer scope.engine.gpa.free(retained);
    retained[0] = c.JS_NewUint32(scope.engine.context, @intFromEnum(kind));
    @memcpy(retained[1..], roots);
    return scope.own(try if (arrow) @import("native_node_function.zig").createArrow(scope.engine, name, length, Adapter.callback, retained) else @import("native_node_function.zig").createMethod(scope.engine, name, length, Adapter.callback, retained));
}
fn key(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Symbol"), "for", &.{try scope.text("node-ignore")});
}
fn define(scope: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(scope.engine.context, object, name, c.JS_DupValue(scope.engine.context, value), 0) < 0) return v.js.capture(scope.engine);
}
fn emptyCache(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Object"), "create", &.{c.pi_js_null()});
}
fn initCache(scope: *Scope, object: c.JSValue) !void {
    try scope.set(object, "_ignoreCache", try emptyCache(scope));
    try scope.set(object, "_testCache", try emptyCache(scope));
}
fn factory(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var arguments = [_]c.JSValue{input(args, 0)};
    return engine.checked(c.JS_CallConstructor(engine.context, roots[0], arguments.len, &arguments));
}
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const supplied = input(args, 0);
    const options = if (c.JS_IsUndefined(supplied)) try scope.object() else supplied;
    const lower = try scope.get(options, "ignorecase");
    const legacy = if (c.JS_IsUndefined(lower)) boolean(&scope, true) else lower;
    const upper = try scope.get(options, "ignoreCase");
    const ignore_case = if (c.JS_IsUndefined(upper)) legacy else upper;
    const allow = try scope.get(options, "allowRelativePaths");
    const object = try scope.own(try @import("native_class.zig").object(engine, target));
    const descriptor = try scope.object();
    try scope.put(descriptor, "value", boolean(&scope, true));
    _ = try scope.invoke(try scope.global("Object"), "defineProperty", &.{ object, roots[1], descriptor });
    var manager_args = [_]c.JSValue{ignore_case};
    const manager = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, roots[0], manager_args.len, &manager_args)));
    try scope.put(object, "_rules", manager);
    try scope.put(object, "_strictPathCheck", boolean(&scope, !scope.truthy(allow)));
    _ = try scope.invoke(object, "_initCache", &.{});
    return c.JS_DupValue(engine.context, object);
}
fn managerConstruct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const manager = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.put(manager, "_ignoreCase", input(args, 0));
    try scope.put(manager, "_rules", try scope.array());
    try scope.put(manager, "_basenameCount", c.JS_NewInt32(engine.context, 0));
    return c.JS_DupValue(engine.context, manager);
}
fn ruleConstruct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const rule = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.put(rule, "pattern", input(args, 0));
    try scope.put(rule, "mark", input(args, 1));
    try scope.put(rule, "negative", input(args, 4));
    try define(&scope, rule, "body", input(args, 2));
    try define(&scope, rule, "ignoreCase", input(args, 3));
    try define(&scope, rule, "regexPrefix", input(args, 5));
    return c.JS_DupValue(engine.context, rule);
}
fn basenameOnly(scope: *Scope, body: c.JSValue) !bool {
    const slash = try scope.invoke(body, "indexOf", &.{try scope.text("/")});
    var offset: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &offset, slash) < 0) return v.js.capture(scope.engine);
    return offset < 0 or offset == @as(i64, try v.length(scope, body)) - 1;
}
fn addOne(scope: *Scope, manager: c.JSValue, value: c.JSValue, rule_constructor: c.JSValue, ignore_key: c.JSValue) !void {
    if (scope.truthy(value) and scope.truthy(try scope.own(try v.js.getKey(scope.engine, value, ignore_key)))) {
        const previous = try scope.get(manager, "_rules");
        const concat = try scope.get(previous, "concat");
        try scope.set(manager, "_rules", try scope.call(concat, previous, &.{try scope.get(try scope.get(value, "_rules"), "_rules")}));
        const count = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, try scope.get(manager, "_basenameCount"), try scope.get(try scope.get(value, "_rules"), "_basenameCount"))));
        try scope.set(manager, "_basenameCount", count);
        try scope.set(manager, "_added", boolean(scope, true));
        return;
    }
    const item = if (c.JS_IsString(value)) block: {
        const object = try scope.object();
        try scope.put(object, "pattern", value);
        break :block object;
    } else value;
    const checked = try scope.get(item, "pattern");
    if (!scope.truthy(checked) or !c.JS_IsString(checked) or try rx.matches(scope, "^ +$", "", checked) or try rx.matches(scope, "(?:[^\\\\]|^)\\\\$", "", checked) or scope.equal(try scope.invoke(checked, "indexOf", &.{try scope.text("#")}), c.JS_NewInt32(scope.engine.context, 0))) return;
    // createRule's argument is evaluated before its destructuring getters.
    const ignore_case = try scope.get(manager, "_ignoreCase");
    const pattern = try scope.get(item, "pattern");
    const mark = try scope.get(item, "mark");
    const negative = scope.equal(try scope.invoke(pattern, "indexOf", &.{try scope.text("!")}), c.JS_NewInt32(scope.engine.context, 0));
    var body = if (negative) try scope.invoke(pattern, "substr", &.{c.JS_NewInt32(scope.engine.context, 1)}) else pattern;
    body = try scope.invoke(body, "replace", &.{ try rx.regex(scope, try scope.text("^\\\\!"), ""), try scope.text("!") });
    body = try scope.invoke(body, "replace", &.{ try rx.regex(scope, try scope.text("^\\\\#"), ""), try scope.text("#") });
    const prefix = try rx.prefix(scope, body);
    var rule_args = [_]c.JSValue{ pattern, mark, body, ignore_case, boolean(scope, negative), prefix };
    const rule = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, rule_constructor, rule_args.len, &rule_args)));
    try scope.set(manager, "_added", boolean(scope, true));
    _ = try scope.invoke(try scope.get(manager, "_rules"), "push", &.{rule});
    if (try basenameOnly(scope, body)) {
        try scope.set(manager, "_basenameCount", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, try scope.get(manager, "_basenameCount"), c.JS_NewInt32(scope.engine.context, 1)))));
    }
}
fn addManager(scope: *Scope, manager: c.JSValue, pattern: c.JSValue) !c.JSValue {
    try scope.set(manager, "_added", boolean(scope, false));
    var patterns = pattern;
    if (c.JS_IsString(pattern)) {
        const split = try scope.invoke(pattern, "split", &.{try rx.regex(scope, try scope.text("\\r?\\n"), "g")});
        patterns = try scope.invoke(split, "filter", &.{try scope.global("Boolean")});
    }
    if (!try v.array(scope, patterns)) {
        const wrapped = try scope.array();
        _ = try scope.invoke(wrapped, "push", &.{patterns});
        patterns = wrapped;
    }
    const for_each = try scope.get(patterns, "forEach");
    _ = try scope.call(for_each, patterns, &.{ try scope.get(manager, "_add"), manager });
    return c.JS_DupValue(scope.engine.context, try scope.get(manager, "_added"));
}
fn normalize(scope: *Scope, original: c.JSValue, platform: c.JSValue) !c.JSValue {
    if (!scope.truthy(original) or !scope.truthy(try scope.get(platform, "windows"))) return original;
    const extended =
        \\^\\\\\?\\
    ;
    if (try rx.matches(scope, extended, "", original) or try rx.matches(scope, "[\"<>|\\u0000-\\u001F]+", "u", original)) return original;
    return scope.invoke(original, "replace", &.{ try rx.regex(scope, try scope.text("\\\\"), "g"), try scope.text("/") });
}
fn pathError(scope: *Scope, kind: enum { type_error, range_error }, message: c.JSValue) anyerror {
    const reason = scope.own(v.js.builtin(scope.engine, if (kind == .type_error) "TypeError" else "RangeError", &.{message}) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn validPath(scope: *Scope, path: c.JSValue, original: c.JSValue, strict: bool, platform: c.JSValue) !bool {
    if (!c.JS_IsString(path)) {
        if (strict) return pathError(scope, .type_error, try scope.concat(try scope.concat(try scope.text("path must be a string, but got `"), try scope.stringify(original)), try scope.text("`")));
        return false;
    }
    if (try v.length(scope, path) == 0) {
        if (strict) return pathError(scope, .type_error, try scope.text("path must not be empty"));
        return false;
    }
    const not_relative = (scope.truthy(try scope.get(platform, "windows")) and try rx.matches(scope, "^[a-z]:/", "i", path)) or try notRelative(scope, path);
    if (not_relative) {
        if (strict) return pathError(scope, .range_error, try scope.concat(try scope.concat(try scope.text("path should be a `path.relative()`d string, but got \""), try scope.stringify(original)), try scope.text("\"")));
        return false;
    }
    return true;
}
fn charCode(scope: *Scope, value: c.JSValue, index: i64) !c.JSValue {
    return scope.invoke(value, "charCodeAt", &.{c.JS_NewInt64(scope.engine.context, index)});
}
fn notRelative(scope: *Scope, path: c.JSValue) !bool {
    const first = try charCode(scope, path, 0);
    if (scope.equal(first, c.JS_NewInt32(scope.engine.context, '/'))) return true;
    if (!scope.equal(first, c.JS_NewInt32(scope.engine.context, '.'))) return false;
    if (try v.length(scope, path) == 1) return true;
    const second = try charCode(scope, path, 1);
    if (scope.equal(second, c.JS_NewInt32(scope.engine.context, '/'))) return true;
    if (!scope.equal(second, c.JS_NewInt32(scope.engine.context, '.'))) return false;
    return try v.length(scope, path) == 2 or scope.equal(try charCode(scope, path, 2), c.JS_NewInt32(scope.engine.context, '/'));
}
fn parent(scope: *Scope, path: c.JSValue) !c.JSValue {
    var double_slash: i32 = -1;
    const starts_slash = scope.equal(try charCode(scope, path, 0), c.JS_NewInt32(scope.engine.context, '/'));
    if (!starts_slash and c.JS_ToInt32(scope.engine.context, &double_slash, try scope.invoke(path, "indexOf", &.{try scope.text("//")})) < 0) return v.js.capture(scope.engine);
    if (starts_slash or double_slash >= 0) {
        const slices = try scope.invoke(try scope.invoke(path, "split", &.{try scope.text("/")}), "filter", &.{try scope.global("Boolean")});
        _ = try scope.invoke(slices, "pop", &.{});
        return if (try v.length(scope, slices) > 0) scope.concat(try scope.invoke(slices, "join", &.{try scope.text("/")}), try scope.text("/")) else scope.text("");
    }
    const length = try v.length(scope, path);
    const trailing = scope.equal(try charCode(scope, path, @as(i64, length) - 1), c.JS_NewInt32(scope.engine.context, '/'));
    const index = try scope.invoke(path, "lastIndexOf", &.{ try scope.text("/"), c.JS_NewInt64(scope.engine.context, @as(i64, length) - (if (trailing) @as(i64, 2) else 1)) });
    var cut: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &cut, index) < 0) return v.js.capture(scope.engine);
    return if (cut < 0) scope.text("") else scope.invoke(path, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt64(scope.engine.context, @as(i64, cut) + 1) });
}
fn basename(scope: *Scope, path: c.JSValue) !c.JSValue {
    const end = @as(i64, try v.length(scope, path)) - 1;
    const last = if (end >= 0) try v.at(scope, path, @intCast(end)) else c.pi_js_undefined();
    const index = try scope.invoke(path, "lastIndexOf", &.{ try scope.text("/"), c.JS_NewInt64(scope.engine.context, if (try v.eq(scope, last, "/")) end - 1 else end) });
    var cut: i32 = -1;
    if (c.JS_ToInt32(scope.engine.context, &cut, index) < 0) return v.js.capture(scope.engine);
    return if (cut < 0) path else scope.invoke(path, "slice", &.{c.JS_NewInt64(scope.engine.context, @as(i64, cut) + 1)});
}
fn testRules(scope: *Scope, manager: c.JSValue, path: c.JSValue, check_unignored: bool, check: bool) !c.JSValue {
    var ignored = false;
    var unignored = false;
    var matched = c.pi_js_undefined();
    const rules = try scope.get(manager, "_rules");
    const length = try v.length(scope, rules);
    var count: f64 = 0;
    if (c.JS_ToFloat64(scope.engine.context, &count, try scope.get(manager, "_basenameCount")) < 0) return v.js.capture(scope.engine);
    const shortcut = count * 2 >= @as(f64, @floatFromInt(length));
    const base = if (shortcut) try basename(scope, path) else path;
    for (0..length) |index| {
        const rule = try v.at(scope, rules, @intCast(index));
        const negative = scope.truthy(try scope.get(rule, "negative"));
        const skip = (unignored == negative and ignored != unignored) or (negative and !ignored and !unignored and !check_unignored);
        if (!skip) {
            const expression = try scope.get(rule, if (check) "checkRegex" else "regex");
            const test_function = try scope.get(expression, "test");
            const selected = if (shortcut and scope.truthy(try scope.get(rule, "_basenameOnly"))) base else path;
            if (!scope.truthy(try scope.call(test_function, expression, &.{selected}))) continue;
            ignored = !negative;
            unignored = negative;
            matched = if (negative) c.pi_js_undefined() else rule;
        }
    }
    const result = try scope.object();
    try scope.put(result, "ignored", boolean(scope, ignored));
    try scope.put(result, "unignored", boolean(scope, unignored));
    if (!c.JS_IsUndefined(matched)) try scope.put(result, "rule", matched);
    return result;
}
fn cachedTest(scope: *Scope, receiver: c.JSValue, path: c.JSValue, cache: c.JSValue, check_unignored: bool) anyerror!c.JSValue {
    if (try v.js.hasKey(scope.engine, cache, path)) return scope.own(try v.js.getKey(scope.engine, cache, path));
    const parent_path = try parent(scope, path);
    const above = if (scope.truthy(parent_path)) try scope.invoke(receiver, "_t", &.{ parent_path, cache, boolean(scope, check_unignored) }) else c.pi_js_undefined();
    const result = if (!c.JS_IsUndefined(above) and scope.truthy(try scope.get(above, "ignored"))) above else try scope.invoke(try scope.get(receiver, "_rules"), "test", &.{ path, boolean(scope, check_unignored), try scope.text("regex") });
    try v.js.setKey(scope.engine, cache, path, result);
    return result;
}
fn testPath(scope: *Scope, receiver: c.JSValue, original: c.JSValue, cache: c.JSValue, check_unignored: bool, platform: c.JSValue) !c.JSValue {
    const path = try normalize(scope, original, platform);
    _ = try validPath(scope, path, original, scope.truthy(try scope.get(receiver, "_strictPathCheck")), platform);
    return scope.invoke(receiver, "_t", &.{ path, cache, boolean(scope, check_unignored) });
}
fn dispatch(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var value: u32 = 0;
    if (c.JS_ToUint32(engine.context, &value, roots[0]) < 0) return v.js.capture(engine);
    const kind: Method = @enumFromInt(value);
    const first = input(args, 0);
    const result = switch (kind) {
        .add => block: {
            if (scope.truthy(try scope.invoke(try scope.get(receiver, "_rules"), "add", &.{first}))) _ = try scope.invoke(receiver, "_initCache", &.{});
            break :block receiver;
        },
        .addPattern => try scope.invoke(receiver, "add", &.{first}),
        .add_one => block: { try addOne(&scope, receiver, first, roots[1], roots[2]); break :block c.pi_js_undefined(); },
        .manager_add => return addManager(&scope, receiver, first),
        .manager_test => try testRules(&scope, receiver, first, scope.truthy(input(args, 1)), try v.eq(&scope, input(args, 2), "checkRegex")),
        .ignores, .test_path => block: {
            const test_function = try scope.get(receiver, "_test");
            const tested = try scope.call(test_function, receiver, &.{ first, try scope.get(receiver, if (kind == .test_path) "_testCache" else "_ignoreCache"), boolean(&scope, kind == .test_path) });
            break :block if (kind == .ignores) try scope.get(tested, "ignored") else tested;
        },
        .test_internal => try testPath(&scope, receiver, first, input(args, 1), scope.truthy(input(args, 2)), roots[1]),
        .t_internal => try cachedTest(&scope, receiver, first, input(args, 1), scope.truthy(input(args, 2))),
        .checkIgnore => block: {
            const length = try v.length(&scope, first);
            if (!scope.equal(try charCode(&scope, first, @as(i64, length) - 1), c.JS_NewInt32(engine.context, '/'))) break :block try scope.invoke(receiver, "test", &.{first});
            const parent_path = try parent(&scope, first);
            if (scope.truthy(parent_path)) {
                const t_function = try scope.get(receiver, "_t");
                const above = try scope.call(t_function, receiver, &.{ parent_path, try scope.get(receiver, "_testCache"), boolean(&scope, true) });
                if (scope.truthy(try scope.get(above, "ignored"))) break :block above;
            }
            break :block try scope.invoke(try scope.get(receiver, "_rules"), "test", &.{ first, boolean(&scope, false), try scope.text("checkRegex") });
        },
        .createFilter => try function(&scope, .filter_path, "", 1, &.{receiver}, true),
        .filter_path => boolean(&scope, !scope.truthy(try scope.invoke(roots[1], "ignores", &.{first}))),
        .filter => block: {
            const paths = if (try v.array(&scope, first)) first else wrapped: {
                const array = try scope.array();
                _ = try scope.invoke(array, "push", &.{first});
                break :wrapped array;
            };
            const filter_function = try scope.get(paths, "filter");
            break :block try scope.call(filter_function, paths, &.{try scope.invoke(receiver, "createFilter", &.{})});
        },
        .valid => boolean(&scope, try validPath(&scope, try normalize(&scope, first, roots[1]), first, false, roots[1])),
        .setup_windows => block: { try scope.set(roots[1], "windows", boolean(&scope, true)); break :block c.pi_js_undefined(); },
        .init_cache => block: { try initCache(&scope, receiver); break :block c.pi_js_undefined(); },
        .rule_regex, .rule_check_regex => block: {
            const name: [*:0]const u8 = if (kind == .rule_regex) "_regex" else "_checkRegex";
            const cached = try scope.get(receiver, name);
            if (scope.truthy(cached)) break :block cached;
            break :block try scope.invoke(receiver, "_make", &.{ try scope.text(if (kind == .rule_regex) "regex" else "checkRegex"), try scope.text(name) });
        },
        .rule_make => block: {
            const compiled = try rx.compile(&scope, try scope.get(receiver, "regexPrefix"), scope.truthy(try scope.get(receiver, "ignoreCase")), try v.eq(&scope, first, "checkRegex"));
            const atom = try v.js.atom(engine, input(args, 1));
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyValue(engine.context, receiver, atom, c.JS_DupValue(engine.context, compiled), 0) < 0) return v.js.capture(engine);
            break :block compiled;
        },
        .rule_basename => block: {
            const matched = boolean(&scope, try basenameOnly(&scope, try scope.get(receiver, "body")));
            try define(&scope, receiver, "_basenameOnly", matched);
            break :block matched;
        },
    };
    return c.JS_DupValue(engine.context, result);
}
/// Returns an ordinary namespace whose default is the native factory. The
/// application can supply that exact function to PackageManager Inputs.ignore.
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const platform = try scope.object();
    try scope.put(platform, "windows", boolean(&scope, @import("builtin").os.tag == .windows));
    const ignore_key = try key(&scope);
    const rule_prototype = try scope.object();
    inline for (.{ .{ "regex", Method.rule_regex }, .{ "checkRegex", Method.rule_check_regex }, .{ "_basenameOnly", Method.rule_basename } }) |entry| {
        const descriptor = try scope.object();
        try scope.put(descriptor, "get", try function(&scope, entry[1], "get " ++ entry[0], 0, &.{}, false));
        try scope.put(descriptor, "configurable", boolean(&scope, true));
        _ = try scope.invoke(try scope.global("Object"), "defineProperty", &.{ rule_prototype, try scope.text(entry[0]), descriptor });
    }
    const make = try function(&scope, .rule_make, "_make", 2, &.{}, false);
    if (c.JS_DefinePropertyValueStr(engine.context, rule_prototype, "_make", c.JS_DupValue(engine.context, make), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    const rule_constructor = try scope.own(try @import("native_class.zig").constructor(engine, "IgnoreRule", 6, rule_prototype, ruleConstruct, &.{}));
    const manager_prototype = try scope.object();
    inline for (.{ .{ "_add", Method.add_one }, .{ "add", Method.manager_add }, .{ "test", Method.manager_test } }) |entry| {
        const method = try function(&scope, entry[1], entry[0], if (entry[1] == .manager_test) 3 else 1, &.{ rule_constructor, ignore_key }, false);
        if (c.JS_DefinePropertyValueStr(engine.context, manager_prototype, entry[0], c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    }
    const manager_constructor = try scope.own(try @import("native_class.zig").constructor(engine, "RuleManager", 1, manager_prototype, managerConstruct, &.{}));
    const prototype = try scope.object();
    inline for (.{ .{ "add", Method.add }, .{ "addPattern", Method.addPattern }, .{ "ignores", Method.ignores }, .{ "test", Method.test_path }, .{ "checkIgnore", Method.checkIgnore }, .{ "createFilter", Method.createFilter }, .{ "filter", Method.filter }, .{ "_initCache", Method.init_cache }, .{ "_test", Method.test_internal }, .{ "_t", Method.t_internal } }) |entry| {
        const method = try function(&scope, entry[1], entry[0], if (entry[1] == .createFilter or entry[1] == .init_cache) 0 else if (entry[1] == .test_internal or entry[1] == .t_internal) 3 else 1, &.{platform}, false);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    }
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "Ignore", 0, prototype, construct, &.{ manager_constructor, ignore_key }));
    const exported = try scope.own(try @import("native_node_function.zig").createArrow(engine, "factory", 1, factory, &.{constructor}));
    try scope.put(exported, "default", exported);
    const valid = try function(&scope, .valid, "isPathValid", 1, &.{platform}, true);
    try scope.put(exported, "isPathValid", valid);
    const setup_key = try scope.invoke(try scope.global("Symbol"), "for", &.{try scope.text("setupWindows")});
    const descriptor = try scope.object();
    try scope.put(descriptor, "value", try function(&scope, .setup_windows, "setupWindows", 0, &.{platform}, true));
    _ = try scope.invoke(try scope.global("Object"), "defineProperty", &.{ exported, setup_key, descriptor });
    const namespace = try scope.object();
    try scope.put(namespace, "default", exported);
    try scope.put(namespace, "isPathValid", valid);
    return c.JS_DupValue(engine.context, namespace);
}
pub fn install(engine: *v.em.Engine) !void {
    const namespace = try create(engine);
    defer engine.freeValue(namespace);
    try engine.registerValueModule("ignore", namespace);
}
