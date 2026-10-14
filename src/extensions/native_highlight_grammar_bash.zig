//! Complete Source highlight.js10.7.3 Bash factory; source-only draft.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
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
fn sourceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("native_highlight_regex.zig").source(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn concat(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const values = try list(s, args);
    const fn_value = try s.own(try s.engine.checked(c.JS_NewCFunction(s.engine.context, sourceCallback, "", 1)));
    return s.invoke(try s.invoke(values, "map", &.{fn_value}), "join", &.{try s.text("")});
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "bash", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const variable = try s.object();
    const braced = try s.object();
    try s.put(braced, "begin", try literal(&s, "\\$\\{"));
    try s.put(braced, "end", try literal(&s, "\\}"));
    const default = try s.object();
    try s.put(default, "begin", try literal(&s, ":-"));
    try s.put(default, "contains", try list(&s, &.{variable}));
    try s.put(braced, "contains", try list(&s, &.{ try s.text("self"), default }));
    const object = try s.global("Object");
    const assign = try s.get(object, "assign");
    const variable_changes = try mode(&s, "variable");
    const simple = try s.object();
    try s.put(simple, "begin", try concat(&s, &.{ try literal(&s, "\\$[\\w\\d#@][\\w\\d_]*"), try s.text("(?![\\w\\d])(?![$])") }));
    try s.put(variable_changes, "variants", try list(&s, &.{ simple, braced }));
    _ = try s.call(assign, object, &.{ variable, variable_changes });
    const subst = try mode(&s, "subst");
    try s.put(subst, "begin", try literal(&s, "\\$\\("));
    try s.put(subst, "end", try literal(&s, "\\)"));
    try s.put(subst, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    const heredoc = try s.object();
    try s.put(heredoc, "begin", try literal(&s, "<<-?\\s*(?=\\w+)"));
    const starts = try s.object();
    const same = try s.get(hljs, "END_SAME_AS_BEGIN");
    const terminator = try s.object();
    try s.put(terminator, "begin", try literal(&s, "(\\w+)"));
    try s.put(terminator, "end", try literal(&s, "(\\w+)"));
    try s.put(terminator, "className", try s.text("string"));
    try s.put(starts, "contains", try list(&s, &.{try s.call(same, hljs, &.{terminator})}));
    try s.put(heredoc, "starts", starts);
    const quote = try mode(&s, "string");
    try s.put(quote, "begin", try literal(&s, "\""));
    try s.put(quote, "end", try literal(&s, "\""));
    try s.put(quote, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), variable, subst }));
    _ = try s.invoke(try s.get(subst, "contains"), "push", &.{quote});
    const escaped_quote = try mode(&s, "");
    try s.put(escaped_quote, "begin", try literal(&s, "\\\\\""));
    const apostrophe = try mode(&s, "string");
    try s.put(apostrophe, "begin", try literal(&s, "'"));
    try s.put(apostrophe, "end", try literal(&s, "'"));
    const arithmetic = try s.object();
    try s.put(arithmetic, "begin", try literal(&s, "\\$\\(\\("));
    try s.put(arithmetic, "end", try literal(&s, "\\)\\)"));
    const base_number = try s.object();
    try s.put(base_number, "begin", try literal(&s, "\\d+#[0-9a-f]+"));
    try s.put(base_number, "className", try s.text("number"));
    try s.put(arithmetic, "contains", try list(&s, &.{ base_number, try s.get(hljs, "NUMBER_MODE"), variable }));
    const shells = try list(&s, &.{ try s.text("fish"), try s.text("bash"), try s.text("zsh"), try s.text("sh"), try s.text("csh"), try s.text("ksh"), try s.text("tcsh"), try s.text("dash"), try s.text("scsh") });
    const shebang = try s.get(hljs, "SHEBANG");
    const shell_options = try s.object();
    try s.put(shell_options, "binary", try s.concat(try s.concat(try s.text("("), try s.stringify(try s.invoke(shells, "join", &.{try s.text("|")}))), try s.text(")")));
    try s.put(shell_options, "relevance", c.JS_NewInt32(engine.context, 10));
    const known_shebang = try s.call(shebang, hljs, &.{shell_options});
    const function = try mode(&s, "function");
    try s.put(function, "begin", try literal(&s, "\\w[\\w\\d_]*\\s*\\(\\s*\\)\\s*\\{"));
    try s.put(function, "returnBegin", c.pi_js_bool(engine.context, 1));
    const inherit = try s.get(hljs, "inherit");
    const title = try s.get(hljs, "TITLE_MODE");
    const title_changes = try s.object();
    try s.put(title_changes, "begin", try literal(&s, "\\w[\\w\\d_]*"));
    try s.put(function, "contains", try list(&s, &.{try s.call(inherit, hljs, &.{ title, title_changes })}));
    try s.put(function, "relevance", c.JS_NewInt32(engine.context, 0));
    const language = try s.object();
    try s.put(language, "name", try s.text("Bash"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("sh"), try s.text("zsh") }));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try literal(&s, "\\b[a-z._-]+\\b"));
    try s.put(keywords, "keyword", try s.text("if then else elif fi for while in do done case esac function"));
    try s.put(keywords, "literal", try s.text("true false"));
    try s.put(keywords, "built_in", try s.text("break cd continue eval exec exit export getopts hash pwd readonly return shift test times trap umask unset alias bind builtin caller command declare echo enable help let local logout mapfile printf read readarray source type typeset ulimit unalias set shopt autoload bg bindkey bye cap chdir clone comparguments compcall compctl compdescribe compfiles compgroups compquote comptags comptry compvalues dirs disable disown echotc echoti emulate fc fg float functions getcap getln history integer jobs kill limit log noglob popd print pushd pushln rehash sched setcap setopt stat suspend ttyctl unfunction unhash unlimit unsetopt vared wait whence where which zcompile zformat zftp zle zmodload zparseopts zprof zpty zregexparse zsocket zstyle ztcp"));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    try s.index(contains, 0, known_shebang);
    try s.index(contains, 1, try s.call(try s.get(hljs, "SHEBANG"), hljs, &.{}));
    try s.index(contains, 2, function);
    try s.index(contains, 3, arithmetic);
    try s.index(contains, 4, try s.get(hljs, "HASH_COMMENT_MODE"));
    try s.index(contains, 5, heredoc);
    try s.index(contains, 6, quote);
    try s.index(contains, 7, escaped_quote);
    try s.index(contains, 8, apostrophe);
    try s.index(contains, 9, variable);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
