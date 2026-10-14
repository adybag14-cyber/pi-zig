//! Full Source highlight.js10.7.3 compileLanguage/compileMode and cloning bodies.
//! Source-only draft; no registered grammar/scanner/public qualification yet.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const extensions = @import("native_highlight_compiler_extensions.zig");
const regex = @import("native_highlight_regex.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const c = em.c;
const Callback = enum(c_int) { compile, dependency, expand, variant, contains, child, begin_rule };

fn function(scope: *Scope, state: c.JSValue, mode: c.JSValue, kind: Callback) !c.JSValue {
    var roots = [_]c.JSValue{ state, mode };
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, if (kind == .compile) "compileMode" else "", if (kind == .compile) 2 else 1, @intFromEnum(kind), roots.len, &roots)));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const first = if (argc > 0) args[0] else c.pi_js_undefined();
    const second = if (argc > 1) args[1] else c.pi_js_undefined();
    return invoke(engine, roots[0], roots[1], @enumFromInt(magic), first, second) catch |err| sdk.fail(engine, err);
}
fn inherit(scope: *Scope, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(state, "inherit"), c.pi_js_undefined(), args);
}
fn dependency(scope: *Scope, state: c.JSValue, mode: c.JSValue) !c.JSValue {
    if (!scope.truthy(mode)) return c.pi_js_bool(scope.engine.context, 0);
    const ends = try scope.get(mode, "endsWithParent");
    if (scope.truthy(ends)) return ends;
    return scope.call(try scope.get(state, "dependency"), c.pi_js_undefined(), &.{try scope.get(mode, "starts")});
}
fn expand(scope: *Scope, state: c.JSValue, mode: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(mode, "variants")) and !scope.truthy(try scope.get(mode, "cachedVariants"))) {
        const variants = try scope.get(mode, "variants");
        const map = try scope.get(variants, "map");
        const mapper = try function(scope, state, mode, .variant);
        try scope.set(mode, "cachedVariants", try scope.call(map, variants, &.{mapper}));
    }
    const cached = try scope.get(mode, "cachedVariants");
    if (scope.truthy(cached)) return cached;
    if (scope.truthy(try dependency(scope, state, mode))) {
        const changes = try scope.object();
        const starts = try scope.get(mode, "starts");
        try scope.put(changes, "starts", if (scope.truthy(starts)) try inherit(scope, state, &.{try scope.get(mode, "starts")}) else c.pi_js_null());
        return inherit(scope, state, &.{ mode, changes });
    }
    const object = try scope.global("Object");
    if (scope.truthy(try scope.invoke(object, "isFrozen", &.{mode}))) return inherit(scope, state, &.{mode});
    return mode;
}
fn invoke(engine: *em.Engine, state: c.JSValue, owner: c.JSValue, kind: Callback, first: c.JSValue, second: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (kind) {
        .compile => try compileMode(&scope, state, first, second),
        .dependency => try dependency(&scope, state, first),
        .expand => try expand(&scope, state, first),
        .variant => value: {
            const changes = try scope.object();
            try scope.put(changes, "variants", c.pi_js_null());
            break :value try inherit(&scope, state, &.{ owner, changes, first });
        },
        .contains => try scope.call(try scope.get(state, "expand"), c.pi_js_undefined(), &.{if (scope.equal(first, try scope.text("self"))) owner else first}),
        .child => value: {
            _ = try scope.call(try scope.get(state, "compile"), c.pi_js_undefined(), &.{ first, owner });
            break :value c.pi_js_undefined();
        },
        .begin_rule => value: {
            const add = try scope.get(owner, "addRule");
            const begin = try scope.get(first, "begin");
            const options = try scope.object();
            try scope.put(options, "rule", first);
            try scope.put(options, "type", try scope.text("begin"));
            break :value try scope.call(add, owner, &.{ begin, options });
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn langRe(scope: *Scope, state: c.JSValue, value: c.JSValue, global: bool) !c.JSValue {
    const constructor = try scope.global("RegExp");
    const source = try scope.own(try regex.source(scope.engine, value));
    const language = try scope.get(state, "language");
    var flags = try scope.text("m");
    flags = try scope.concat(flags, try scope.text(if (scope.truthy(try scope.get(language, "case_insensitive"))) "i" else ""));
    flags = try scope.concat(flags, try scope.text(if (global) "g" else ""));
    var args = [_]c.JSValue{ source, flags };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
fn sourceError(scope: *Scope, message: []const u8) !c.JSValue {
    const constructor = try scope.global("Error");
    var args = [_]c.JSValue{try scope.text(message)};
    const reason = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
    _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason));
    return js.capture(scope.engine);
}
fn remove(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DeleteProperty(scope.engine.context, object, atom, c.JS_PROP_THROW) < 0) return js.capture(scope.engine);
}
fn compileMode(scope: *Scope, state: c.JSValue, mode: c.JSValue, parent: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(mode, "isCompiled"))) return mode;
    const early = try scope.array();
    try scope.index(early, 0, try scope.get(state, "compileMatch"));
    try runExtensions(scope, early, mode, parent);
    const custom = try scope.get(try scope.get(state, "language"), "compilerExtensions");
    // Custom extensions are actual caller callbacks; no native replacement or
    // successful default body is supplied. Source ignores each return value.
    try runExtensions(scope, custom, mode, parent);
    try scope.set(mode, "__beforeBegin", c.pi_js_null());
    const late = try scope.array();
    inline for (.{ "beginKeywords", "compileIllegal", "compileRelevance" }, 0..) |name, index| try scope.index(late, index, try scope.get(state, name));
    try runExtensions(scope, late, mode, parent);
    try scope.set(mode, "isCompiled", c.pi_js_bool(scope.engine.context, 1));
    var pattern = c.pi_js_null();
    const raw_keywords = try scope.get(mode, "keywords");
    if ((c.JS_IsObject(raw_keywords) and !c.JS_IsFunction(scope.engine.context, raw_keywords)) or c.JS_IsNull(raw_keywords)) {
        const keywords = try scope.get(mode, "keywords");
        pattern = try scope.get(keywords, "$pattern");
        try remove(scope, try scope.get(mode, "keywords"), "$pattern");
    }
    if (scope.truthy(try scope.get(mode, "keywords"))) {
        const keywords = try scope.get(mode, "keywords");
        const insensitive = try scope.get(try scope.get(state, "language"), "case_insensitive");
        try scope.set(mode, "keywords", try scope.own(try @import("native_highlight_keywords.zig").compile(scope.engine, keywords, insensitive, c.pi_js_undefined())));
    }
    if (scope.truthy(try scope.get(mode, "lexemes")) and scope.truthy(pattern)) return sourceError(scope, "ERR: Prefer `keywords.$pattern` to `mode.lexemes`, BOTH are not allowed. (see mode reference) ");
    if (!scope.truthy(pattern)) pattern = try scope.get(mode, "lexemes");
    if (!scope.truthy(pattern)) {
        var args = [_]c.JSValue{try scope.text("\\w+")};
        pattern = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
    }
    try scope.set(mode, "keywordPatternRe", try langRe(scope, state, pattern, true));
    if (scope.truthy(parent)) {
        if (!scope.truthy(try scope.get(mode, "begin"))) try scope.set(mode, "begin", try boundary(scope));
        try scope.set(mode, "beginRe", try langRe(scope, state, try scope.get(mode, "begin"), false));
        if (scope.truthy(try scope.get(mode, "endSameAsBegin"))) try scope.set(mode, "end", try scope.get(mode, "begin"));
        if (!scope.truthy(try scope.get(mode, "end")) and !scope.truthy(try scope.get(mode, "endsWithParent"))) try scope.set(mode, "end", try boundary(scope));
        if (scope.truthy(try scope.get(mode, "end"))) try scope.set(mode, "endRe", try langRe(scope, state, try scope.get(mode, "end"), false));
        const end = try scope.own(try regex.source(scope.engine, try scope.get(mode, "end")));
        try scope.set(mode, "terminatorEnd", if (scope.truthy(end)) end else try scope.text(""));
        if (scope.truthy(try scope.get(mode, "endsWithParent")) and scope.truthy(try scope.get(parent, "terminatorEnd"))) {
            const prior = try scope.get(mode, "terminatorEnd");
            const suffix = try scope.concat(try scope.text(if (scope.truthy(try scope.get(mode, "end"))) "|" else ""), try scope.get(parent, "terminatorEnd"));
            try scope.set(mode, "terminatorEnd", try scope.concat(prior, suffix));
        }
    }
    if (scope.truthy(try scope.get(mode, "illegal"))) try scope.set(mode, "illegalRe", try langRe(scope, state, try scope.get(mode, "illegal"), false));
    if (!scope.truthy(try scope.get(mode, "contains"))) try scope.set(mode, "contains", try scope.array());
    const empty = try scope.array();
    const concat = try scope.get(empty, "concat");
    const contains = try scope.get(mode, "contains");
    const map = try scope.get(contains, "map");
    const expanded = try scope.call(map, contains, &.{try function(scope, state, mode, .contains)});
    const spread = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, expanded, null));
    const count = try sdk.length(scope.engine, spread);
    const arguments = try scope.engine.gpa.alloc(c.JSValue, count);
    defer scope.engine.gpa.free(arguments);
    for (arguments, 0..) |*value, index| value.* = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, spread, @intCast(index))));
    try scope.set(mode, "contains", try scope.call(concat, empty, arguments));
    const children = try scope.get(mode, "contains");
    _ = try scope.invoke(children, "forEach", &.{try function(scope, state, mode, .child)});
    if (scope.truthy(try scope.get(mode, "starts"))) _ = try scope.call(try scope.get(state, "compile"), c.pi_js_undefined(), &.{ try scope.get(mode, "starts"), parent });
    const constructor = try scope.get(state, "matcherConstructor");
    const matcher = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 0, null)));
    const terms = try scope.get(mode, "contains");
    _ = try scope.invoke(terms, "forEach", &.{try function(scope, state, matcher, .begin_rule)});
    inline for (.{ .{ "terminatorEnd", "end" }, .{ "illegal", "illegal" } }) |entry| {
        if (scope.truthy(try scope.get(mode, entry[0]))) {
            const add = try scope.get(matcher, "addRule");
            const value = try scope.get(mode, entry[0]);
            const options = try scope.object();
            try scope.put(options, "type", try scope.text(entry[1]));
            _ = try scope.call(add, matcher, &.{ value, options });
        }
    }
    try scope.set(mode, "matcher", matcher);
    return mode;
}
fn boundary(scope: *Scope) !c.JSValue {
    var args = [_]c.JSValue{try scope.text("\\B|\\b")};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn customExtension(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.call(engine, if (argc > 0) args[0] else c.pi_js_undefined(), c.pi_js_undefined(), roots[0..2]) catch |err| sdk.fail(engine, err);
}
fn runExtensions(scope: *Scope, list: c.JSValue, mode: c.JSValue, parent: c.JSValue) !void {
    const for_each = try scope.get(list, "forEach");
    var roots = [_]c.JSValue{ mode, parent };
    const callback_value = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, customExtension, "", 1, 0, roots.len, &roots)));
    _ = try scope.call(for_each, list, &.{callback_value});
}
pub fn compile(engine: *em.Engine, language: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try scope.get(options, "plugins"); // Source parameter destructuring.
    const state = try scope.object();
    try scope.put(state, "language", language);
    try scope.put(state, "inherit", try scope.own(try @import("native_highlight_inherit.zig").create(engine)));
    try scope.put(state, "matcherConstructor", try scope.own(try @import("native_highlight_resumable_regex.zig").constructor(engine, language)));
    inline for (.{ .{ "compileMatch", extensions.Kind.match }, .{ "beginKeywords", extensions.Kind.begin_keywords }, .{ "compileIllegal", extensions.Kind.illegal }, .{ "compileRelevance", extensions.Kind.relevance } }) |entry| try scope.put(state, entry[0], try scope.own(try extensions.create(engine, entry[1])));
    inline for (.{ .{ "compile", Callback.compile }, .{ "dependency", Callback.dependency }, .{ "expand", Callback.expand } }) |entry| try scope.put(state, entry[0], try function(&scope, state, c.pi_js_undefined(), entry[1]));
    if (!scope.truthy(try scope.get(language, "compilerExtensions"))) try scope.set(language, "compilerExtensions", try scope.array());
    if (scope.truthy(try scope.get(language, "contains")) and scope.truthy(try scope.invoke(try scope.get(language, "contains"), "includes", &.{try scope.text("self")}))) return sourceError(&scope, "ERR: contains `self` is not supported at the top-level of a language.  See documentation.");
    const aliases = try scope.get(language, "classNameAliases");
    try scope.set(language, "classNameAliases", try inherit(&scope, state, &.{if (scope.truthy(aliases)) aliases else try scope.object()}));
    return c.JS_DupValue(engine.context, try scope.call(try scope.get(state, "compile"), c.pi_js_undefined(), &.{language}));
}
