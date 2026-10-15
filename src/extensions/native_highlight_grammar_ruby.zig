//! Complete Source highlight.js10.7.3 Ruby factory; source-only draft.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const method_re = "([a-zA-Z_]\\w*[!?=]?|[-+~]@|<<|>>|=~|===?|<=>|[<>]=?|\\*\\*|[-/+%^&*~`|]|\\[\\]=?)";
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn literal(s: *Scope, text: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(text)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn mode(s: *Scope, name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(name));
    return result;
}
fn sourceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("native_highlight_regex.zig").source(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn concat(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const values = try list(s, args);
    const fn_value = try s.own(try s.engine.checked(c.JS_NewCFunction(s.engine.context, sourceCallback, "", 1)));
    return s.invoke(try s.invoke(values, "map", &.{fn_value}), "join", &.{try s.text("")});
}
fn lookahead(s: *Scope, value: c.JSValue) !c.JSValue {
    return concat(s, &.{ try s.text("(?="), value, try s.text(")") });
}
fn title(s: *Scope, hljs: c.JSValue, pattern: []const u8) !c.JSValue {
    const inherit = try s.get(hljs, "inherit");
    const base = try s.get(hljs, "TITLE_MODE");
    const changes = try s.object();
    try s.put(changes, "begin", try s.text(pattern));
    return s.call(inherit, hljs, &.{ base, changes });
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "ruby", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("and then defined module in return redo if BEGIN retry end for self when next until do begin unless END rescue else break undef not super class case require yield alias while ensure elsif or include attr_reader attr_writer attr_accessor __FILE__"));
    try s.put(keywords, "built_in", try s.text("proc lambda"));
    try s.put(keywords, "literal", try s.text("true false nil"));
    const yard = try mode(&s, "doctag");
    try s.put(yard, "begin", try s.text("@[A-Za-z]+"));
    const irb_object = try s.object();
    try s.put(irb_object, "begin", try s.text("#<"));
    try s.put(irb_object, "end", try s.text(">"));
    const comments = try s.array();
    inline for (.{ .{ "#", "$" }, .{ "^=begin", "^=end" } }, 0..) |entry, index| {
        const fn_value = try s.get(hljs, "COMMENT");
        const options = try s.object();
        try s.put(options, "contains", try list(&s, &.{yard}));
        if (index == 1) try s.put(options, "relevance", c.JS_NewInt32(engine.context, 10));
        try s.index(comments, index, try s.call(fn_value, hljs, &.{ try s.text(entry[0]), try s.text(entry[1]), options }));
    }
    try s.index(comments, 2, try s.call(try s.get(hljs, "COMMENT"), hljs, &.{ try s.text("^__END__"), try s.text("\\n$") }));
    const subst = try mode(&s, "subst");
    try s.put(subst, "begin", try literal(&s, "#\\{"));
    try s.put(subst, "end", try literal(&s, "\\}"));
    try s.put(subst, "keywords", keywords);
    const string = try mode(&s, "string");
    try s.put(string, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst }));
    const variants = try s.array();
    inline for (.{ .{ "'", "'" }, .{ "\"", "\"" }, .{ "`", "`" }, .{ "%[qQwWx]?\\(", "\\)" }, .{ "%[qQwWx]?\\[", "\\]" }, .{ "%[qQwWx]?\\{", "\\}" }, .{ "%[qQwWx]?<", ">" }, .{ "%[qQwWx]?/", "/" }, .{ "%[qQwWx]?%", "%" }, .{ "%[qQwWx]?-", "-" }, .{ "%[qQwWx]?\\|", "\\|" } }, 0..) |entry, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, entry[0]));
        try s.put(variant, "end", try literal(&s, entry[1]));
        try s.index(variants, index, variant);
    }
    inline for (.{ "\\B\\?(\\\\\\d{1,3})", "\\B\\?(\\\\x[A-Fa-f0-9]{1,2})", "\\B\\?(\\\\u\\{?[A-Fa-f0-9]{1,6}\\}?)", "\\B\\?(\\\\M-\\\\C-|\\\\M-\\\\c|\\\\c\\\\M-|\\\\M-|\\\\C-\\\\M-)[\\x20-\\x7e]", "\\B\\?\\\\(c|C-)[\\x20-\\x7e]", "\\B\\?\\\\?\\S" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, pattern));
        try s.index(variants, index + 11, variant);
    }
    const heredoc = try s.object();
    try s.put(heredoc, "begin", try literal(&s, "<<[-~]?'?(\\w+)\\n(?:[^\\n]*\\n)*?\\s*\\1\\b"));
    try s.put(heredoc, "returnBegin", c.pi_js_bool(engine.context, 1));
    const intro = try s.object();
    try s.put(intro, "begin", try literal(&s, "<<[-~]?'?"));
    const same = try s.get(hljs, "END_SAME_AS_BEGIN");
    const delimiter = try s.object();
    try s.put(delimiter, "begin", try literal(&s, "(\\w+)"));
    try s.put(delimiter, "end", try literal(&s, "(\\w+)"));
    try s.put(delimiter, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst }));
    try s.put(heredoc, "contains", try list(&s, &.{ intro, try s.call(same, hljs, &.{delimiter}) }));
    try s.index(variants, 17, heredoc);
    try s.put(string, "variants", variants);
    const decimal = "[1-9](_?[0-9])*|0";
    const digits = "[0-9](_?[0-9])*";
    const number = try mode(&s, "number");
    try s.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    const numbers = try s.array();
    inline for (.{ "\\b(" ++ decimal ++ ")(\\.(" ++ digits ++ "))?([eE][+-]?(" ++ digits ++ ")|r)?i?\\b", "\\b0[dD][0-9](_?[0-9])*r?i?\\b", "\\b0[bB][0-1](_?[0-1])*r?i?\\b", "\\b0[oO][0-7](_?[0-7])*r?i?\\b", "\\b0[xX][0-9a-fA-F](_?[0-9a-fA-F])*r?i?\\b", "\\b0(_?[0-7])+r?i?\\b" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(numbers, index, variant);
    }
    try s.put(number, "variants", numbers);
    const params = try mode(&s, "params");
    try s.put(params, "begin", try s.text("\\("));
    try s.put(params, "end", try s.text("\\)"));
    try s.put(params, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(params, "keywords", keywords);
    const defaults = try s.array();
    try s.index(defaults, 0, string);
    const class_mode = try mode(&s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("class module"));
    try s.put(class_mode, "end", try s.text("$|;"));
    try s.put(class_mode, "illegal", try literal(&s, "="));
    const class_children = try s.array();
    try s.index(class_children, 0, try title(&s, hljs, "[A-Za-z_]\\w*(::\\w+)*(\\?|!)?"));
    const ancestor = try s.object();
    try s.put(ancestor, "begin", try s.text("<\\s*"));
    const ancestor_name = try s.object();
    try s.put(ancestor_name, "begin", try s.concat(try s.concat(try s.concat(try s.text("("), try s.get(hljs, "IDENT_RE")), try s.text("::)?")), try s.get(hljs, "IDENT_RE")));
    try s.put(ancestor_name, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(ancestor, "contains", try list(&s, &.{ancestor_name}));
    try s.index(class_children, 1, ancestor);
    try s.put(class_mode, "contains", try s.invoke(class_children, "concat", &.{comments}));
    try s.index(defaults, 1, class_mode);
    const function = try mode(&s, "function");
    try s.put(function, "begin", try concat(&s, &.{ try literal(&s, "def\\s+"), try lookahead(&s, try s.text(method_re ++ "\\s*(\\(|;|$)")) }));
    try s.put(function, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(function, "keywords", try s.text("def"));
    try s.put(function, "end", try s.text("$|;"));
    try s.put(function, "contains", try s.invoke(try list(&s, &.{ try title(&s, hljs, method_re), params }), "concat", &.{comments}));
    try s.index(defaults, 2, function);
    const namespace = try s.object();
    try s.put(namespace, "begin", try s.concat(try s.get(hljs, "IDENT_RE"), try s.text("::")));
    try s.index(defaults, 3, namespace);
    const symbol_key = try mode(&s, "symbol");
    try s.put(symbol_key, "begin", try s.concat(try s.get(hljs, "UNDERSCORE_IDENT_RE"), try s.text("(!|\\?)?:")));
    try s.put(symbol_key, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(defaults, 4, symbol_key);
    const symbol = try mode(&s, "symbol");
    try s.put(symbol, "begin", try s.text(":(?!\\s)"));
    const symbol_method = try s.object();
    try s.put(symbol_method, "begin", try s.text(method_re));
    try s.put(symbol, "contains", try list(&s, &.{ string, symbol_method }));
    try s.put(symbol, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(defaults, 5, symbol);
    try s.index(defaults, 6, number);
    const variable = try mode(&s, "variable");
    try s.put(variable, "begin", try s.text("(\\$\\W)|((\\$|@@?)(\\w+))(?=[^@$?])(?![A-Za-z])(?![@$?'])"));
    try s.index(defaults, 7, variable);
    const block_params = try mode(&s, "params");
    try s.put(block_params, "begin", try literal(&s, "\\|"));
    try s.put(block_params, "end", try literal(&s, "\\|"));
    try s.put(block_params, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(block_params, "keywords", keywords);
    try s.index(defaults, 8, block_params);
    const regex_container = try s.object();
    try s.put(regex_container, "begin", try s.concat(try s.concat(try s.text("("), try s.get(hljs, "RE_STARTERS_RE")), try s.text("|unless)\\s*")));
    try s.put(regex_container, "keywords", try s.text("unless"));
    const regexp = try mode(&s, "regexp");
    try s.put(regexp, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst }));
    try s.put(regexp, "illegal", try literal(&s, "\\n"));
    const regex_variants = try s.array();
    inline for (.{ .{ "/", "/[a-z]*", false }, .{ "%r\\{", "\\}[a-z]*", true }, .{ "%r\\(", "\\)[a-z]*", false }, .{ "%r!", "![a-z]*", false }, .{ "%r\\[", "\\][a-z]*", false } }, 0..) |entry, index| {
        const variant = try s.object();
        try s.put(variant, "begin", if (entry[2]) try literal(&s, entry[0]) else try s.text(entry[0]));
        try s.put(variant, "end", if (entry[2]) try literal(&s, entry[1]) else try s.text(entry[1]));
        try s.index(regex_variants, index, variant);
    }
    try s.put(regexp, "variants", regex_variants);
    try s.put(regex_container, "contains", try s.invoke(try list(&s, &.{regexp}), "concat", &.{ irb_object, comments }));
    try s.put(regex_container, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(defaults, 9, regex_container);
    const all_defaults = try s.invoke(defaults, "concat", &.{ irb_object, comments });
    try s.set(subst, "contains", all_defaults);
    try s.set(params, "contains", all_defaults);
    const irb = try s.array();
    const result_prompt = try s.object();
    try s.put(result_prompt, "begin", try literal(&s, "^\\s*=>"));
    const result_starts = try s.object();
    try s.put(result_starts, "end", try s.text("$"));
    try s.put(result_starts, "contains", all_defaults);
    try s.put(result_prompt, "starts", result_starts);
    try s.index(irb, 0, result_prompt);
    const prompt = try mode(&s, "meta");
    try s.put(prompt, "begin", try s.text("^([>?]>|[\\w#]+\\(\\w+\\):\\d+:\\d+>|(\\w+-)?\\d+\\.\\d+\\.\\d+(p\\d+)?[^\\d][^>]+>)(?=[ ])"));
    const prompt_starts = try s.object();
    try s.put(prompt_starts, "end", try s.text("$"));
    try s.put(prompt_starts, "contains", all_defaults);
    try s.put(prompt, "starts", prompt_starts);
    try s.index(irb, 1, prompt);
    _ = try s.invoke(comments, "unshift", &.{irb_object});
    const language = try s.object();
    try s.put(language, "name", try s.text("Ruby"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("rb"), try s.text("gemspec"), try s.text("podspec"), try s.text("thor"), try s.text("irb") }));
    try s.put(language, "keywords", keywords);
    try s.put(language, "illegal", try literal(&s, "/\\*"));
    const shebang = try s.get(hljs, "SHEBANG");
    const options = try s.object();
    try s.put(options, "binary", try s.text("ruby"));
    var contains = try list(&s, &.{try s.call(shebang, hljs, &.{options})});
    contains = try s.invoke(contains, "concat", &.{irb});
    contains = try s.invoke(contains, "concat", &.{comments});
    contains = try s.invoke(contains, "concat", &.{all_defaults});
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
