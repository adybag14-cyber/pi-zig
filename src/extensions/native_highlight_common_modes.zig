//! Complete Source highlight.js10.7.3 common mode declarations and helper bodies.
//! Source-only grammar dependency; recursive freezing/core registration are separate.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const ordinary = @import("native_node_function.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const regex = @import("native_highlight_regex.zig");
const c = em.c;
const Kind = enum(i32) { comment, shebang, shebang_begin, same, same_begin, same_end };
const number = "\\b\\d+(\\.\\d+)?";
const c_number = "(-?)(\\b0[xX][a-fA-F0-9]+|(\\b\\d+(\\.\\d*)?|\\.\\d+)([eE][-+]?\\d+)?)";
fn literal(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(pattern)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try scope.array();
    for (values, 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
fn helper(scope: *Scope, state: c.JSValue, kind: Kind, name: [*:0]const u8, arity: u8) !c.JSValue {
    var roots = [_]c.JSValue{ state, c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)) };
    if (kind == .comment or kind == .same) return scope.own(try @import("native_legacy_function.zig").create(scope.engine, name, arity, invoke, &roots));
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, arrowCallback, name, arity, 0, roots.len, &roots)));
}
fn arrowCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, c.pi_js_undefined(), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn inherit(scope: *Scope, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(state, "inherit"), c.pi_js_undefined(), args);
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var numeric: i32 = 0;
    if (c.JS_ToInt32(engine.context, &numeric, roots[1]) < 0) return js.capture(engine);
    const state = roots[0];
    const first = argument(args, 0);
    const second = argument(args, 1);
    const result = switch (@as(Kind, @enumFromInt(numeric))) {
        .comment => value: {
            const options = if (c.JS_IsUndefined(argument(args, 2))) try scope.object() else argument(args, 2);
            const base = try scope.object();
            try scope.put(base, "className", try scope.text("comment"));
            try scope.put(base, "begin", first);
            try scope.put(base, "end", second);
            try scope.put(base, "contains", try scope.array());
            const mode = try inherit(&scope, state, &.{ base, options });
            _ = try scope.invoke(try scope.get(mode, "contains"), "push", &.{try scope.get(state, "phrasal")});
            const tag = try scope.object();
            try scope.put(tag, "className", try scope.text("doctag"));
            try scope.put(tag, "begin", try scope.text("(?:TODO|FIXME|NOTE|BUG|OPTIMIZE|HACK|XXX):"));
            try scope.put(tag, "relevance", c.JS_NewInt32(engine.context, 0));
            _ = try scope.invoke(try scope.get(mode, "contains"), "push", &.{tag});
            break :value mode;
        },
        .shebang => value: {
            const options = if (c.JS_IsUndefined(first)) try scope.object() else first;
            const begin = try literal(&scope, "^#![ ]*/");
            if (scope.truthy(try scope.get(options, "binary"))) {
                // concat maps Source regex sources in the left-to-right argument order.
                var combined = try scope.own(try regex.source(engine, begin));
                combined = try scope.concat(combined, try scope.text(".*\\b"));
                const binary = try scope.own(try regex.source(engine, try scope.get(options, "binary")));
                // Array.join converts null/undefined regex source to an empty string.
                combined = try scope.concat(combined, if (c.JS_IsNull(binary) or c.JS_IsUndefined(binary)) try scope.text("") else try scope.stringify(binary));
                combined = try scope.concat(combined, try scope.text("\\b.*"));
                try scope.set(options, "begin", combined);
            }
            const base = try scope.object();
            try scope.put(base, "className", try scope.text("meta"));
            try scope.put(base, "begin", begin);
            try scope.put(base, "end", try literal(&scope, "$"));
            try scope.put(base, "relevance", c.JS_NewInt32(engine.context, 0));
            try scope.put(base, "on:begin", try helper(&scope, state, .shebang_begin, "on:begin", 2));
            break :value try inherit(&scope, state, &.{ base, options });
        },
        .shebang_begin => value: {
            if (!scope.equal(try scope.get(first, "index"), c.JS_NewInt32(engine.context, 0))) _ = try scope.invoke(second, "ignoreMatch", &.{});
            break :value c.pi_js_undefined();
        },
        .same => value: {
            const changes = try scope.object();
            try scope.put(changes, "on:begin", try helper(&scope, state, .same_begin, "on:begin", 2));
            try scope.put(changes, "on:end", try helper(&scope, state, .same_end, "on:end", 2));
            break :value try scope.invoke(try scope.global("Object"), "assign", &.{ first, changes });
        },
        .same_begin => value: {
            const data = try scope.get(second, "data");
            try scope.set(data, "_beginMatch", try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, first, 1))));
            break :value c.pi_js_undefined();
        },
        .same_end => value: {
            const data = try scope.get(second, "data");
            const begin = try scope.get(data, "_beginMatch");
            const end = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, first, 1)));
            if (!scope.equal(begin, end)) _ = try scope.invoke(second, "ignoreMatch", &.{});
            break :value c.pi_js_undefined();
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn numberMode(scope: *Scope, begin: []const u8) !c.JSValue {
    const mode = try scope.object();
    try scope.put(mode, "className", try scope.text("number"));
    try scope.put(mode, "begin", try scope.text(begin));
    try scope.put(mode, "relevance", c.JS_NewInt32(scope.engine.context, 0));
    return mode;
}
pub fn create(engine: *em.Engine, inherit_function: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "inherit", inherit_function);
    const phrasal = try scope.object();
    try scope.put(phrasal, "begin", try literal(&scope, "\\b(a|an|the|are|I'm|isn't|don't|doesn't|won't|but|just|should|pretty|simply|enough|gonna|going|wtf|so|such|will|you|your|they|like|more)\\b"));
    try scope.put(state, "phrasal", phrasal);
    const escape = try scope.object();
    try scope.put(escape, "begin", try scope.text("\\\\[\\s\\S]"));
    try scope.put(escape, "relevance", c.JS_NewInt32(engine.context, 0));
    const strings = try scope.array();
    inline for (.{ "'", "\"" }, 0..) |delimiter, index| {
        const mode = try scope.object();
        try scope.put(mode, "className", try scope.text("string"));
        try scope.put(mode, "begin", try scope.text(delimiter));
        try scope.put(mode, "end", try scope.text(delimiter));
        try scope.put(mode, "illegal", try scope.text("\\n"));
        try scope.put(mode, "contains", try list(&scope, &.{escape}));
        try scope.index(strings, index, mode);
    }
    const comment = try helper(&scope, state, .comment, "COMMENT", 2);
    const regex_mode = try scope.object();
    try scope.put(regex_mode, "begin", try literal(&scope, "(?=/[^/\\n]*/)"));
    const inner_regex = try scope.object();
    try scope.put(inner_regex, "className", try scope.text("regexp"));
    try scope.put(inner_regex, "begin", try literal(&scope, "/"));
    try scope.put(inner_regex, "end", try literal(&scope, "/[gimuy]*"));
    try scope.put(inner_regex, "illegal", try literal(&scope, "\\n"));
    const brackets = try scope.object();
    try scope.put(brackets, "begin", try literal(&scope, "\\["));
    try scope.put(brackets, "end", try literal(&scope, "\\]"));
    try scope.put(brackets, "relevance", c.JS_NewInt32(engine.context, 0));
    try scope.put(brackets, "contains", try list(&scope, &.{escape}));
    try scope.put(inner_regex, "contains", try list(&scope, &.{ escape, brackets }));
    try scope.put(regex_mode, "contains", try list(&scope, &.{inner_regex}));
    const modes = try scope.invoke(try scope.global("Object"), "create", &.{c.pi_js_null()});
    try scope.put(modes, "MATCH_NOTHING_RE", try literal(&scope, "\\b\\B"));
    inline for (.{ .{ "IDENT_RE", "[a-zA-Z]\\w*" }, .{ "UNDERSCORE_IDENT_RE", "[a-zA-Z_]\\w*" }, .{ "NUMBER_RE", number }, .{ "C_NUMBER_RE", c_number }, .{ "BINARY_NUMBER_RE", "\\b(0b[01]+)" }, .{ "RE_STARTERS_RE", "!|!=|!==|%|%=|&|&&|&=|\\*|\\*=|\\+|\\+=|,|-|-=|/=|/|:|;|<<|<<=|<=|<|===|==|=|>>>=|>>=|>=|>>>|>>|>|\\?|\\[|\\{|\\(|\\^|\\^=|\\||\\|=|\\|\\||~" } }) |item| try scope.put(modes, item[0], try scope.text(item[1]));
    try scope.put(modes, "SHEBANG", try helper(&scope, state, .shebang, "SHEBANG", 0));
    try scope.put(modes, "BACKSLASH_ESCAPE", escape);
    try scope.put(modes, "APOS_STRING_MODE", try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, strings, 0))));
    try scope.put(modes, "QUOTE_STRING_MODE", try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, strings, 1))));
    try scope.put(modes, "PHRASAL_WORDS_MODE", phrasal);
    try scope.put(modes, "COMMENT", comment);
    inline for (.{ .{ "C_LINE_COMMENT_MODE", "//", "$" }, .{ "C_BLOCK_COMMENT_MODE", "/\\*", "\\*/" }, .{ "HASH_COMMENT_MODE", "#", "$" } }) |item| try scope.put(modes, item[0], try scope.call(comment, c.pi_js_undefined(), &.{ try scope.text(item[1]), try scope.text(item[2]) }));
    inline for (.{ .{ "NUMBER_MODE", number }, .{ "C_NUMBER_MODE", c_number }, .{ "BINARY_NUMBER_MODE", "\\b(0b[01]+)" }, .{ "CSS_NUMBER_MODE", number ++ "(%|em|ex|ch|rem|vw|vh|vmin|vmax|cm|mm|in|pt|pc|px|deg|grad|rad|turn|s|ms|Hz|kHz|dpi|dpcm|dppx)?" } }) |item| try scope.put(modes, item[0], try numberMode(&scope, item[1]));
    try scope.put(modes, "REGEXP_MODE", regex_mode);
    inline for (.{ .{ "TITLE_MODE", "[a-zA-Z]\\w*" }, .{ "UNDERSCORE_TITLE_MODE", "[a-zA-Z_]\\w*" } }) |item| {
        const mode = try scope.object();
        try scope.put(mode, "className", try scope.text("title"));
        try scope.put(mode, "begin", try scope.text(item[1]));
        try scope.put(mode, "relevance", c.JS_NewInt32(engine.context, 0));
        try scope.put(modes, item[0], mode);
    }
    const guard = try scope.object();
    try scope.put(guard, "begin", try scope.text("\\.\\s*[a-zA-Z_]\\w*"));
    try scope.put(guard, "relevance", c.JS_NewInt32(engine.context, 0));
    try scope.put(modes, "METHOD_GUARD", guard);
    try scope.put(modes, "END_SAME_AS_BEGIN", try helper(&scope, state, .same, "END_SAME_AS_BEGIN", 1));
    return c.JS_DupValue(engine.context, try scope.invoke(try scope.global("Object"), "freeze", &.{modes}));
}
