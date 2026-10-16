//! Native ignore 7.0.8 factory for actual PackageManager discovery.
//! No host glob approximation and no embedded JavaScript implementation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const rx = @import("native_ignore7_regex.zig");
const Scope = v.Scope;
const c = v.c;
const Method = enum { add, addPattern, ignores, test_path, checkIgnore, createFilter, filter, filter_path, add_one, valid, setup_windows, init_cache };
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
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
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
    _ = try scope.invoke(try scope.global("Object"), "defineProperty", &.{ object, try key(&scope), descriptor });
    const manager = try scope.object();
    try scope.put(manager, "_ignoreCase", ignore_case);
    try scope.put(manager, "_rules", try scope.array());
    try scope.put(manager, "_basenameCount", c.JS_NewInt32(engine.context, 0));
    try scope.put(object, "_rules", manager);
    try scope.put(object, "_strictPathCheck", boolean(&scope, !scope.truthy(allow)));
    _ = try scope.invoke(object, "_initCache", &.{});
    return c.JS_DupValue(engine.context, object);
}
fn addOne(scope: *Scope, manager: c.JSValue, value: c.JSValue) !void {
    if (scope.truthy(value) and scope.truthy(try scope.own(try v.js.getKey(scope.engine, value, try key(scope))))) {
        const other = try scope.get(value, "_rules");
        try scope.set(manager, "_rules", try scope.invoke(try scope.get(manager, "_rules"), "concat", &.{try scope.get(other, "_rules")}));
        const count = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, try scope.get(manager, "_basenameCount"), try scope.get(other, "_basenameCount"))));
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
    const rule = try scope.object();
    try scope.put(rule, "pattern", pattern);
    try scope.put(rule, "mark", mark);
    try scope.put(rule, "negative", boolean(scope, negative));
    try define(scope, rule, "body", body);
    try define(scope, rule, "ignoreCase", ignore_case);
    try define(scope, rule, "regexPrefix", prefix);
    try scope.set(manager, "_added", boolean(scope, true));
    _ = try scope.invoke(try scope.get(manager, "_rules"), "push", &.{rule});
    const slash = try scope.invoke(body, "indexOf", &.{try scope.text("/")});
    var offset: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &offset, slash) < 0) return v.js.capture(scope.engine);
    if (offset < 0 or offset == @as(i64, try v.length(scope, body)) - 1) {
        try scope.set(manager, "_basenameCount", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, try scope.get(manager, "_basenameCount"), c.JS_NewInt32(scope.engine.context, 1)))));
    }
}
fn add(scope: *Scope, receiver: c.JSValue, pattern: c.JSValue) !c.JSValue {
    const manager = try scope.get(receiver, "_rules");
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
    _ = try scope.invoke(patterns, "forEach", &.{ try function(scope, .add_one, "_add", 1, &.{manager}, false), manager });
    if (scope.truthy(try scope.get(manager, "_added"))) _ = try scope.invoke(receiver, "_initCache", &.{});
    return c.JS_DupValue(scope.engine.context, receiver);
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
fn ruleRegex(scope: *Scope, rule: c.JSValue, check: bool) !c.JSValue {
    const name: [*:0]const u8 = if (check) "_checkRegex" else "_regex";
    const cached = try scope.get(rule, name);
    if (scope.truthy(cached)) return cached;
    const compiled = try rx.compile(scope, try scope.get(rule, "regexPrefix"), scope.truthy(try scope.get(rule, "ignoreCase")), check);
    try define(scope, rule, name, compiled);
    return compiled;
}
fn testRules(scope: *Scope, manager: c.JSValue, path: c.JSValue, check_unignored: bool, check: bool) !c.JSValue {
    var ignored = false;
    var unignored = false;
    var matched = c.pi_js_undefined();
    const rules = try scope.get(manager, "_rules");
    const length = try v.length(scope, rules);
    // The primary basename shortcut is a measured optimization; scanning the
    // same full path preserves exactly the rule language and parent result.
    for (0..length) |index| {
        const rule = try v.at(scope, rules, @intCast(index));
        const negative = scope.truthy(try scope.get(rule, "negative"));
        const skip = (unignored == negative and ignored != unignored) or (negative and !ignored and !unignored and !check_unignored);
        if (!skip and scope.truthy(try scope.invoke(try ruleRegex(scope, rule, check), "test", &.{path}))) {
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
    const above = if (scope.truthy(parent_path)) try cachedTest(scope, receiver, parent_path, cache, check_unignored) else c.pi_js_undefined();
    const result = if (!c.JS_IsUndefined(above) and scope.truthy(try scope.get(above, "ignored"))) above else try testRules(scope, try scope.get(receiver, "_rules"), path, check_unignored, false);
    try v.js.setKey(scope.engine, cache, path, result);
    return result;
}
fn testPath(scope: *Scope, receiver: c.JSValue, original: c.JSValue, check_unignored: bool, platform: c.JSValue) !c.JSValue {
    const path = try normalize(scope, original, platform);
    _ = try validPath(scope, path, original, scope.truthy(try scope.get(receiver, "_strictPathCheck")), platform);
    return cachedTest(scope, receiver, path, try scope.get(receiver, if (check_unignored) "_testCache" else "_ignoreCache"), check_unignored);
}
fn dispatch(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var value: u32 = 0;
    if (c.JS_ToUint32(engine.context, &value, roots[0]) < 0) return v.js.capture(engine);
    const kind: Method = @enumFromInt(value);
    const first = input(args, 0);
    const result = switch (kind) {
        .add => return add(&scope, receiver, first),
        .addPattern => try scope.invoke(receiver, "add", &.{first}),
        .add_one => block: { try addOne(&scope, roots[1], first); break :block c.pi_js_undefined(); },
        .ignores => try scope.get(try testPath(&scope, receiver, first, false, roots[1]), "ignored"),
        .test_path => try testPath(&scope, receiver, first, true, roots[1]),
        .checkIgnore => block: {
            const length = try v.length(&scope, first);
            if (!scope.equal(try charCode(&scope, first, @as(i64, length) - 1), c.JS_NewInt32(engine.context, '/'))) break :block try scope.invoke(receiver, "test", &.{first});
            const parent_path = try parent(&scope, first);
            if (scope.truthy(parent_path)) {
                const above = try cachedTest(&scope, receiver, parent_path, try scope.get(receiver, "_testCache"), true);
                if (scope.truthy(try scope.get(above, "ignored"))) break :block above;
            }
            break :block try testRules(&scope, try scope.get(receiver, "_rules"), first, false, true);
        },
        .createFilter => try function(&scope, .filter_path, "", 1, &.{receiver}, true),
        .filter_path => boolean(&scope, !scope.truthy(try scope.invoke(roots[1], "ignores", &.{first}))),
        .filter => block: {
            const paths = if (try v.array(&scope, first)) first else wrapped: {
                const array = try scope.array();
                _ = try scope.invoke(array, "push", &.{first});
                break :wrapped array;
            };
            break :block try scope.invoke(paths, "filter", &.{try scope.invoke(receiver, "createFilter", &.{})});
        },
        .valid => boolean(&scope, try validPath(&scope, try normalize(&scope, first, roots[1]), first, false, roots[1])),
        .setup_windows => block: { try scope.set(roots[1], "windows", boolean(&scope, true)); break :block c.pi_js_undefined(); },
        .init_cache => block: { try initCache(&scope, receiver); break :block c.pi_js_undefined(); },
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
    const prototype = try scope.object();
    inline for (.{ .{ "add", Method.add }, .{ "addPattern", Method.addPattern }, .{ "ignores", Method.ignores }, .{ "test", Method.test_path }, .{ "checkIgnore", Method.checkIgnore }, .{ "createFilter", Method.createFilter }, .{ "filter", Method.filter }, .{ "_initCache", Method.init_cache } }) |entry| {
        const method = try function(&scope, entry[1], entry[0], if (entry[1] == .createFilter or entry[1] == .init_cache) 0 else 1, &.{platform}, false);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    }
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "Ignore", 0, prototype, construct, &.{}));
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
