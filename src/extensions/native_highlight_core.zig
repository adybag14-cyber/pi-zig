//! Source-only computational highlight.js10.7.3 core bodies used by SDK syntax.
//! Real registration/highlight/autodetection/plugins; no DOM API facades.
//! Eager installation requires every actual factory before any registration.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const legacy = @import("native_legacy_function.zig");
const c = em.c;
const Kind = enum(i32) { highlight, private_highlight, auto, configure, register, unregister, list, get, aliases, require, detect, plugin, debug, safe, alias_each, fire_each, plugin_before, plugin_after, auto_map, sort };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn key(s: *Scope, obj: c.JSValue, name: c.JSValue) !c.JSValue {
    return s.own(try js.getKey(s.engine, obj, name));
}
fn op(s: *Scope, kind: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, kind, a, b)));
}
fn function(s: *Scope, state: c.JSValue, kind: Kind, name: [*:0]const u8, length: c_int) !c.JSValue {
    return s.own(try legacy.create(s.engine, name, length, invoke, &.{ state, c.JS_NewInt32(s.engine.context, @intFromEnum(kind)) }));
}
fn callback(s: *Scope, state: c.JSValue, kind: Kind) !c.JSValue {
    if (kind == .fire_each) return function(s, state, kind, "", 1);
    var roots = [_]c.JSValue{ state, c.JS_NewInt32(s.engine.context, @intFromEnum(kind)) };
    return s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, arrowCallback, "", if (kind == .sort) 2 else 1, 0, roots.len, &roots)));
}
fn arrowCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, c.pi_js_undefined(), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(engine, err);
}
fn call(s: *Scope, state: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(state, name), c.pi_js_undefined(), args);
}
fn remove(s: *Scope, obj: c.JSValue, name: c.JSValue) !void {
    const atom = c.JS_ValueToAtom(s.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DeleteProperty(s.engine.context, obj, atom, c.JS_PROP_THROW) < 0) return js.capture(s.engine);
}
fn sourceError(s: *Scope, message: c.JSValue) !void {
    var args = [_]c.JSValue{message};
    const error_value = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, try s.global("Error"), args.len, &args)));
    _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, error_value));
    return js.capture(s.engine);
}
fn getterLanguage(s: *Scope, state: c.JSValue, value: c.JSValue) !c.JSValue {
    const name = try s.invoke(if (s.truthy(value)) value else try s.text(""), "toLowerCase", &.{});
    const languages = try s.get(state, "languages");
    const direct = try key(s, languages, name);
    return if (s.truthy(direct)) direct else try key(s, languages, try key(s, try s.get(state, "aliases"), name));
}
fn fire(s: *Scope, state: c.JSValue, event: []const u8, value: c.JSValue) !void {
    const data = try s.object();
    try s.put(data, "event", try s.text(event));
    try s.put(data, "value", value);
    _ = try s.invoke(try s.get(state, "plugins"), "forEach", &.{try callback(s, data, .fire_each)});
}
fn aliases(s: *Scope, state: c.JSValue, list_value: c.JSValue, options: c.JSValue) !void {
    const language = try s.get(options, "languageName");
    var values = list_value;
    if (c.JS_IsString(values)) {
        values = try s.array();
        try s.index(values, 0, list_value);
    }
    const roots = try s.object();
    try s.put(roots, "aliases", try s.get(state, "aliases"));
    try s.put(roots, "languageName", language);
    _ = try s.invoke(values, "forEach", &.{try callback(s, roots, .alias_each)});
}
fn register(s: *Scope, state: c.JSValue, name: c.JSValue, definition: c.JSValue) !void {
    const language = s.call(definition, c.pi_js_undefined(), &.{try s.get(state, "api")}) catch |err| blk: {
        if (err != error.JavaScriptException) return err;
        const reason = try s.own(c.JS_DupValue(s.engine.context, s.engine.captured_exception orelse return err));
        _ = try call(s, state, "error", &.{try s.invoke(try s.text("Language definition for '{}' could not be registered."), "replace", &.{ try s.text("{}"), name })});
        if (!s.truthy(try s.get(state, "safeMode"))) {
            _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason));
            return js.capture(s.engine);
        }
        _ = try call(s, state, "error", &.{reason});
        break :blk try s.get(state, "plaintext");
    };
    if (!s.truthy(try s.get(language, "name"))) try s.set(language, "name", name);
    try js.setKey(s.engine, try s.get(state, "languages"), name, language);
    try s.set(language, "rawDefinition", try s.invoke(definition, "bind", &.{ c.pi_js_null(), try s.get(state, "api") }));
    if (s.truthy(try s.get(language, "aliases"))) {
        const options = try s.object();
        try s.put(options, "languageName", name);
        try aliases(s, state, try s.get(language, "aliases"), options);
    }
}
fn justText(s: *Scope, state: c.JSValue, code: c.JSValue) !c.JSValue {
    const result = try s.object();
    try s.put(result, "relevance", c.JS_NewInt32(s.engine.context, 0));
    const options = try s.get(state, "options");
    const constructor = try s.get(options, "__emitter");
    var args = [_]c.JSValue{try s.get(state, "options")};
    try s.put(result, "emitter", try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, args.len, &args))));
    try s.put(result, "value", try @import("native_highlight_classes.zig").escapeHtml(s, code));
    try s.put(result, "illegal", c.pi_js_bool(s.engine.context, 0));
    try s.put(result, "top", try s.get(state, "plaintext"));
    _ = try s.invoke(try s.get(result, "emitter"), "addText", &.{code});
    return result;
}
fn auto(s: *Scope, state: c.JSValue, code: c.JSValue, input: c.JSValue) !c.JSValue {
    var subset = input;
    if (!s.truthy(subset)) subset = try s.get(try s.get(state, "options"), "languages");
    if (!s.truthy(subset)) subset = try s.invoke(try s.global("Object"), "keys", &.{try s.get(state, "languages")});
    const plaintext = try justText(s, state, code);
    const filtered = try s.invoke(subset, "filter", &.{try s.get(state, "getLanguage")});
    const detected = try s.invoke(filtered, "filter", &.{try s.get(state, "autoDetection")});
    const data = try s.object();
    try s.put(data, "state", state);
    try s.put(data, "code", code);
    const results = try s.invoke(detected, "map", &.{try callback(s, data, .auto_map)});
    _ = try s.invoke(results, "unshift", &.{plaintext});
    const sorted = try s.invoke(results, "sort", &.{try callback(s, state, .sort)});
    const pair = try @import("native_highlight_scanner.zig").destructurePair(s, sorted);
    const result = pair[0];
    try s.set(result, "second_best", pair[1]);
    return result;
}
fn highlight(s: *Scope, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var code = try s.text("");
    var name = try s.text("");
    var ignore = arg(args, 2);
    var continuation = arg(args, 3);
    const options = arg(args, 1);
    // typeof null is object in the real Source overload discriminator.
    if ((c.JS_IsObject(options) and !c.JS_IsFunction(s.engine.context, options)) or c.JS_IsNull(options)) {
        code = arg(args, 0);
        ignore = try s.get(options, "ignoreIllegals");
        name = try s.get(options, "language");
        continuation = c.pi_js_undefined();
    } else {
        _ = try call(s, state, "deprecated", &.{ try s.text("10.7.0"), try s.text("highlight(lang, code, ...args) has been deprecated.") });
        _ = try call(s, state, "deprecated", &.{ try s.text("10.7.0"), try s.text("Please use highlight(code, options) instead.\nhttps://github.com/highlightjs/highlight.js/issues/2277") });
        name = arg(args, 0);
        code = options;
    }
    const context = try s.object();
    try s.put(context, "code", code);
    try s.put(context, "language", name);
    try fire(s, state, "before:highlight", context);
    const supplied = try s.get(context, "result");
    const result = if (s.truthy(supplied)) try s.get(context, "result") else try call(s, state, "_highlight", &.{ try s.get(context, "language"), try s.get(context, "code"), ignore, continuation });
    try s.set(result, "code", try s.get(context, "code"));
    try fire(s, state, "after:highlight", result);
    return result;
}
fn upgrade(s: *Scope, state: c.JSValue, plugin: c.JSValue) !void {
    _ = state;
    inline for (.{ .{ "before:highlightBlock", "before:highlightElement", Kind.plugin_before }, .{ "after:highlightBlock", "after:highlightElement", Kind.plugin_after } }) |entry| {
        if (s.truthy(try s.get(plugin, entry[0])) and !s.truthy(try s.get(plugin, entry[1]))) try s.set(plugin, entry[1], try callback(s, plugin, entry[2]));
    }
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var id: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &id, roots[1]) < 0) return js.capture(engine);
    const state = roots[0];
    const first = arg(args, 0);
    const second = arg(args, 1);
    const result = switch (@as(Kind, @enumFromInt(id))) {
        .highlight => try highlight(&s, state, args),
        .private_highlight => try s.own(try @import("native_highlight_scanner.zig").highlight(engine, state, first, second, arg(args, 2), arg(args, 3))),
        .auto => try auto(&s, state, first, second),
        .get => try getterLanguage(&s, state, first),
        .list => try s.invoke(try s.global("Object"), "keys", &.{try s.get(state, "languages")}),
        .register => blk: {
            try register(&s, state, first, second);
            break :blk c.pi_js_undefined();
        },
        .unregister => blk: {
            try remove(&s, try s.get(state, "languages"), first);
            const names = try s.invoke(try s.global("Object"), "keys", &.{try s.get(state, "aliases")});
            const spread = try s.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, names, null));
            const count = try sdk.length(engine, spread);
            for (0..count) |index| {
                const alias = try s.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, spread, @intCast(index))));
                if (s.equal(try key(&s, try s.get(state, "aliases"), alias), first)) try remove(&s, try s.get(state, "aliases"), alias);
            }
            break :blk c.pi_js_undefined();
        },
        .aliases => blk: {
            try aliases(&s, state, first, second);
            break :blk c.pi_js_undefined();
        },
        .alias_each => blk: {
            try js.setKey(engine, try s.get(state, "aliases"), try s.invoke(first, "toLowerCase", &.{}), try s.get(state, "languageName"));
            break :blk c.pi_js_undefined();
        },
        .detect => blk: {
            const language = try getterLanguage(&s, state, first);
            break :blk if (s.truthy(language)) c.pi_js_bool(engine.context, @intFromBool(!s.truthy(try s.get(language, "disableAutodetect")))) else language;
        },
        .require => blk: {
            _ = try call(&s, state, "deprecated", &.{ try s.text("10.4.0"), try s.text("requireLanguage will be removed entirely in v11.") });
            _ = try call(&s, state, "deprecated", &.{ try s.text("10.4.0"), try s.text("Please see https://github.com/highlightjs/highlight.js/pull/2844") });
            const language = try getterLanguage(&s, state, first);
            if (s.truthy(language)) break :blk language;
            try sourceError(&s, try s.invoke(try s.text("The '{}' language is required, but not loaded."), "replace", &.{ try s.text("{}"), first }));
            unreachable;
        },
        .configure => blk: {
            if (s.truthy(try s.get(first, "useBR"))) {
                _ = try call(&s, state, "deprecated", &.{ try s.text("10.3.0"), try s.text("'useBR' will be removed entirely in v11.0") });
                _ = try call(&s, state, "deprecated", &.{ try s.text("10.3.0"), try s.text("Please see https://github.com/highlightjs/highlight.js/issues/2559") });
            }
            try s.set(state, "options", try call(&s, state, "inherit", &.{ try s.get(state, "options"), first }));
            break :blk c.pi_js_undefined();
        },
        .plugin => blk: {
            try upgrade(&s, state, first);
            _ = try s.invoke(try s.get(state, "plugins"), "push", &.{first});
            break :blk c.pi_js_undefined();
        },
        .fire_each => blk: {
            const event = try s.get(state, "event");
            if (s.truthy(try key(&s, first, event))) _ = try s.call(try key(&s, first, event), first, &.{try s.get(state, "value")});
            break :blk c.pi_js_undefined();
        },
        .plugin_before, .plugin_after => blk: {
            const method: [*:0]const u8 = if (id == @intFromEnum(Kind.plugin_before)) "before:highlightBlock" else "after:highlightBlock";
            const fn_value = try s.get(state, method);
            const base = try s.object();
            try s.put(base, "block", try s.get(first, "el"));
            const data = try s.invoke(try s.global("Object"), "assign", &.{ base, first });
            _ = try s.call(fn_value, state, &.{data});
            break :blk c.pi_js_undefined();
        },
        .debug, .safe => blk: {
            try s.set(state, "safeMode", c.pi_js_bool(engine.context, @intFromBool(id == @intFromEnum(Kind.safe))));
            break :blk c.pi_js_undefined();
        },
        .auto_map => try call(&s, try s.get(state, "state"), "_highlight", &.{ first, try s.get(state, "code"), c.pi_js_bool(engine.context, 0) }),
        .sort => blk: {
            const left = try s.get(first, "relevance");
            const right = try s.get(second, "relevance");
            if (!s.equal(left, right)) break :blk try op(&s, 1, right, left);
            if (s.truthy(try s.get(first, "language")) and s.truthy(try s.get(second, "language"))) {
                if (s.equal(try s.get(try getterLanguage(&s, state, try s.get(first, "language")), "supersetOf"), try s.get(second, "language"))) break :blk c.JS_NewInt32(engine.context, 1);
                if (s.equal(try s.get(try getterLanguage(&s, state, try s.get(second, "language")), "supersetOf"), try s.get(first, "language"))) break :blk c.JS_NewInt32(engine.context, -1);
            }
            break :blk c.JS_NewInt32(engine.context, 0);
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn literal(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var args = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
/// computational core only. Loggers are real native error/deprecated bodies.
/// DOM functions remain absent; this object is not exported as full highlight.js.
pub fn create(engine: *em.Engine, loggers: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    const api = try s.object();
    try s.put(state, "api", api);
    const object = try s.global("Object");
    try s.put(state, "languages", try s.invoke(object, "create", &.{c.pi_js_null()}));
    try s.put(state, "aliases", try s.invoke(object, "create", &.{c.pi_js_null()}));
    try s.put(state, "plugins", try s.array());
    try s.put(state, "safeMode", c.pi_js_bool(engine.context, 1));
    const plaintext = try s.object();
    try s.put(plaintext, "disableAutodetect", c.pi_js_bool(engine.context, 1));
    try s.put(plaintext, "name", try s.text("Plain text"));
    try s.put(plaintext, "contains", try s.array());
    try s.put(state, "plaintext", plaintext);
    const classes = try s.own(try @import("native_highlight_classes.zig").create(engine));
    try s.put(state, "Response", try s.get(classes, "Response"));
    const options = try s.object();
    try s.put(options, "noHighlightRe", try literal(&s, "^(no-?highlight)$", "i"));
    try s.put(options, "languageDetectRe", try literal(&s, "\\blang(?:uage)?-([\\w-]+)\\b", "i"));
    try s.put(options, "classPrefix", try s.text("hljs-"));
    try s.put(options, "tabReplace", c.pi_js_null());
    try s.put(options, "useBR", c.pi_js_bool(engine.context, 0));
    try s.put(options, "languages", c.pi_js_null());
    try s.put(options, "__emitter", try s.get(classes, "TokenTreeEmitter"));
    try s.put(state, "options", options);
    try s.put(state, "error", try s.get(loggers, "error"));
    try s.put(state, "deprecated", try s.get(loggers, "deprecated"));
    const inherit = try s.own(try @import("native_highlight_inherit.zig").createLegacyPrototype(engine));
    try s.put(state, "inherit", inherit);
    inline for (.{ .{ "highlight", 4, Kind.highlight }, .{ "highlightAuto", 2, Kind.auto }, .{ "configure", 1, Kind.configure }, .{ "registerLanguage", 2, Kind.register }, .{ "unregisterLanguage", 1, Kind.unregister }, .{ "listLanguages", 0, Kind.list }, .{ "getLanguage", 1, Kind.get }, .{ "registerAliases", 2, Kind.aliases }, .{ "requireLanguage", 1, Kind.require }, .{ "autoDetection", 1, Kind.detect }, .{ "addPlugin", 1, Kind.plugin }, .{ "debugMode", 0, Kind.debug }, .{ "safeMode", 0, Kind.safe } }) |entry| {
        const value = try function(&s, state, entry[2], entry[0], entry[1]);
        try s.put(api, entry[0], value);
        if (entry[2] != Kind.aliases and entry[2] != Kind.safe and entry[2] != Kind.debug) try s.put(state, entry[0], value);
    }
    try s.put(state, "_highlight", try function(&s, state, .private_highlight, "_highlight", 4));
    try s.put(api, "inherit", inherit);
    try s.put(api, "versionString", try s.text("10.7.3"));
    const modes = try s.own(try @import("native_highlight_common_modes.zig").create(engine, inherit));
    try @import("native_highlight_deep_freeze.zig").freezeModeValues(engine, modes);
    _ = try s.invoke(object, "assign", &.{ api, modes });
    return c.JS_DupValue(engine.context, api);
}
pub const eager_order = [_][:0]const u8{ "python", "java", "go", "javascript", "json", "cpp", "typescript", "php", "ruby", "c", "csharp", "nix", "bash", "rust", "scala", "kotlin", "swift", "dart", "groovy", "perl", "lua" };
pub fn registerEager(engine: *em.Engine, api: c.JSValue, factories: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var values: [eager_order.len]c.JSValue = undefined;
    // Boundary admission: missing implementation is never Source plaintext success.
    for (eager_order, 0..) |name, index| {
        values[index] = try key(&s, factories, try s.text(name));
        if (!c.JS_IsFunction(engine.context, values[index])) return error.NativeEagerGrammarBodyUnavailable;
    }
    for (eager_order, 0..) |name, index| _ = try s.invoke(api, "registerLanguage", &.{ try s.text(name), values[index] });
}
