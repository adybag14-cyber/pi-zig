//! Complete Source highlight.js10.7.3 PHP factory; source-only draft.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const c = em.c;
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
fn quoteCopy(s: *Scope, hljs: c.JSValue, name: [*:0]const u8, subst: ?c.JSValue) !c.JSValue {
    const inherit = try s.get(hljs, "inherit");
    const base = try s.get(hljs, name);
    const changes = try s.object();
    try s.put(changes, "illegal", c.pi_js_null());
    if (subst) |value| try s.put(changes, "contains", try s.invoke(try s.get(try s.get(hljs, "QUOTE_STRING_MODE"), "contains"), "concat", &.{value}));
    return s.call(inherit, hljs, &.{ base, changes });
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "php", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const variable = try mode(&s, "variable");
    try s.put(variable, "begin", try s.text("\\$+[a-zA-Z_\x7f-ÿ][a-zA-Z0-9_\x7f-ÿ]*(?![A-Za-z0-9])(?![$])"));
    const preprocessor = try mode(&s, "meta");
    const pre_variants = try s.array();
    inline for (.{ "<\\?php", "<\\?[=]?", "\\?>" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, pattern));
        if (index == 0) try s.put(variant, "relevance", c.JS_NewInt32(engine.context, 10));
        try s.index(pre_variants, index, variant);
    }
    try s.put(preprocessor, "variants", pre_variants);
    const subst = try mode(&s, "subst");
    const short_subst = try s.object();
    try s.put(short_subst, "begin", try literal(&s, "\\$\\w+"));
    const braced_subst = try s.object();
    try s.put(braced_subst, "begin", try literal(&s, "\\{\\$"));
    try s.put(braced_subst, "end", try literal(&s, "\\}"));
    try s.put(subst, "variants", try list(&s, &.{ short_subst, braced_subst }));
    const single = try quoteCopy(&s, hljs, "APOS_STRING_MODE", null);
    const double = try quoteCopy(&s, hljs, "QUOTE_STRING_MODE", subst);
    const same = try s.get(hljs, "END_SAME_AS_BEGIN");
    const heredoc_mode = try s.object();
    try s.put(heredoc_mode, "begin", try literal(&s, "<<<[ \\t]*(\\w+)\\n"));
    try s.put(heredoc_mode, "end", try literal(&s, "[ \\t]*(\\w+)\\b"));
    try s.put(heredoc_mode, "contains", try s.invoke(try s.get(try s.get(hljs, "QUOTE_STRING_MODE"), "contains"), "concat", &.{subst}));
    const heredoc = try s.call(same, hljs, &.{heredoc_mode});
    const string = try mode(&s, "string");
    try s.put(string, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), preprocessor }));
    const strings = try s.array();
    inline for (.{ "b'", "b\"" }, 0..) |start, index| {
        const inherit = try s.get(hljs, "inherit");
        const changes = try s.object();
        try s.put(changes, "begin", try s.text(start));
        try s.put(changes, "end", try s.text(if (index == 0) "'" else "\""));
        try s.index(strings, index, try s.call(inherit, hljs, &.{ if (index == 0) single else double, changes }));
    }
    try s.index(strings, 2, double);
    try s.index(strings, 3, single);
    try s.index(strings, 4, heredoc);
    try s.put(string, "variants", strings);
    const number = try mode(&s, "number");
    const numbers = try s.array();
    inline for (.{ "\\b0b[01]+(?:_[01]+)*\\b", "\\b0o[0-7]+(?:_[0-7]+)*\\b", "\\b0x[\\da-f]+(?:_[\\da-f]+)*\\b", "(?:\\b\\d+(?:_\\d+)*(\\.(?:\\d+(?:_\\d+)*))?|\\B\\.\\d+)(?:e[+-]?\\d+)?" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(numbers, index, variant);
    }
    try s.put(number, "variants", numbers);
    try s.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("__CLASS__ __DIR__ __FILE__ __FUNCTION__ __LINE__ __METHOD__ __NAMESPACE__ __TRAIT__ die echo exit include include_once print require require_once array abstract and as binary bool boolean break callable case catch class clone const continue declare default do double else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum eval extends final finally float for foreach from global goto if implements instanceof insteadof int integer interface isset iterable list match|0 mixed new object or private protected public real return string switch throw trait try unset use var void while xor yield"));
    try s.put(keywords, "literal", try s.text("false null true"));
    try s.put(keywords, "built_in", try s.text("Error|0 AppendIterator ArgumentCountError ArithmeticError ArrayIterator ArrayObject AssertionError BadFunctionCallException BadMethodCallException CachingIterator CallbackFilterIterator CompileError Countable DirectoryIterator DivisionByZeroError DomainException EmptyIterator ErrorException Exception FilesystemIterator FilterIterator GlobIterator InfiniteIterator InvalidArgumentException IteratorIterator LengthException LimitIterator LogicException MultipleIterator NoRewindIterator OutOfBoundsException OutOfRangeException OuterIterator OverflowException ParentIterator ParseError RangeException RecursiveArrayIterator RecursiveCachingIterator RecursiveCallbackFilterIterator RecursiveDirectoryIterator RecursiveFilterIterator RecursiveIterator RecursiveIteratorIterator RecursiveRegexIterator RecursiveTreeIterator RegexIterator RuntimeException SeekableIterator SplDoublyLinkedList SplFileInfo SplFileObject SplFixedArray SplHeap SplMaxHeap SplMinHeap SplObjectStorage SplObserver SplObserver SplPriorityQueue SplQueue SplStack SplSubject SplSubject SplTempFileObject TypeError UnderflowException UnexpectedValueException UnhandledMatchError ArrayAccess Closure Generator Iterator IteratorAggregate Serializable Stringable Throwable Traversable WeakReference WeakMap Directory __PHP_Incomplete_Class parent php_user_filter self static stdClass"));
    const language = try s.object();
    try s.put(language, "aliases", try list(&s, &.{ try s.text("php3"), try s.text("php4"), try s.text("php5"), try s.text("php6"), try s.text("php7"), try s.text("php8") }));
    try s.put(language, "case_insensitive", c.pi_js_bool(engine.context, 1));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "HASH_COMMENT_MODE"));
    const line_comment = try s.get(hljs, "COMMENT");
    const line_options = try s.object();
    try s.put(line_options, "contains", try list(&s, &.{preprocessor}));
    try s.index(contains, 1, try s.call(line_comment, hljs, &.{ try s.text("//"), try s.text("$"), line_options }));
    const block_comment = try s.get(hljs, "COMMENT");
    const block_options = try s.object();
    const doctag = try mode(&s, "doctag");
    try s.put(doctag, "begin", try s.text("@[A-Za-z]+"));
    try s.put(block_options, "contains", try list(&s, &.{doctag}));
    try s.index(contains, 2, try s.call(block_comment, hljs, &.{ try s.text("/\\*"), try s.text("\\*/"), block_options }));
    const halt_comment = try s.get(hljs, "COMMENT");
    const halt_options = try s.object();
    try s.put(halt_options, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.put(halt_options, "keywords", try s.text("__halt_compiler"));
    try s.index(contains, 3, try s.call(halt_comment, hljs, &.{ try s.text("__halt_compiler.+?;"), c.pi_js_bool(engine.context, 0), halt_options }));
    try s.index(contains, 4, preprocessor);
    const this = try mode(&s, "keyword");
    try s.put(this, "begin", try literal(&s, "\\$this\\b"));
    try s.index(contains, 5, this);
    try s.index(contains, 6, variable);
    const composed = try s.object();
    try s.put(composed, "begin", try literal(&s, "(::|->)+[a-zA-Z_\x7f-ÿ][a-zA-Z0-9_\x7f-ÿ]*"));
    try s.index(contains, 7, composed);
    const function = try mode(&s, "function");
    try s.put(function, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(function, "beginKeywords", try s.text("fn function"));
    try s.put(function, "end", try literal(&s, "[;{]"));
    try s.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(function, "illegal", try s.text("[$%\\[]"));
    const use = try s.object();
    try s.put(use, "beginKeywords", try s.text("use"));
    const title = try s.get(hljs, "UNDERSCORE_TITLE_MODE");
    const arrow = try s.object();
    try s.put(arrow, "begin", try s.text("=>"));
    try s.put(arrow, "endsParent", c.pi_js_bool(engine.context, 1));
    const params = try mode(&s, "params");
    try s.put(params, "begin", try s.text("\\("));
    try s.put(params, "end", try s.text("\\)"));
    try s.put(params, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(params, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(params, "keywords", keywords);
    try s.put(params, "contains", try list(&s, &.{ try s.text("self"), variable, try s.get(hljs, "C_BLOCK_COMMENT_MODE"), string, number }));
    try s.put(function, "contains", try list(&s, &.{ use, title, arrow, params }));
    try s.index(contains, 8, function);
    const class_mode = try mode(&s, "class");
    const declarations = try s.array();
    inline for (.{ .{ "enum", "[($\"]" }, .{ "class interface trait", "[:($\"]" } }, 0..) |entry, index| {
        const variant = try s.object();
        try s.put(variant, "beginKeywords", try s.text(entry[0]));
        try s.put(variant, "illegal", try literal(&s, entry[1]));
        try s.index(declarations, index, variant);
    }
    try s.put(class_mode, "variants", declarations);
    try s.put(class_mode, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(class_mode, "end", try literal(&s, "\\{"));
    try s.put(class_mode, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const extends = try s.object();
    try s.put(extends, "beginKeywords", try s.text("extends implements"));
    try s.put(class_mode, "contains", try list(&s, &.{ extends, try s.get(hljs, "UNDERSCORE_TITLE_MODE") }));
    try s.index(contains, 9, class_mode);
    const namespace = try s.object();
    try s.put(namespace, "beginKeywords", try s.text("namespace"));
    try s.put(namespace, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(namespace, "end", try s.text(";"));
    try s.put(namespace, "illegal", try literal(&s, "[.']"));
    try s.put(namespace, "contains", try list(&s, &.{try s.get(hljs, "UNDERSCORE_TITLE_MODE")}));
    try s.index(contains, 10, namespace);
    const use_namespace = try s.object();
    try s.put(use_namespace, "beginKeywords", try s.text("use"));
    try s.put(use_namespace, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(use_namespace, "end", try s.text(";"));
    try s.put(use_namespace, "contains", try list(&s, &.{try s.get(hljs, "UNDERSCORE_TITLE_MODE")}));
    try s.index(contains, 11, use_namespace);
    try s.index(contains, 12, string);
    try s.index(contains, 13, number);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
