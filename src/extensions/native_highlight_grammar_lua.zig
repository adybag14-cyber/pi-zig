//! Complete Source highlight.js10.7.3 Lua factory body; private source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const opening = "\\[=*\\[";
const closing = "\\]=*\\]";
const builtins = "_G _ENV _VERSION __index __newindex __mode __call __metatable __tostring __len __gc __add __sub __mul __div __mod __pow __concat __unm __eq __lt __le assert collectgarbage dofile error getfenv getmetatable ipairs load loadfile loadstring module next pairs pcall print rawequal rawget rawset require select setfenv setmetatable tonumber tostring type unpack xpcall arg self coroutine resume yield status wrap create running debug getupvalue debug sethook getmetatable gethook setmetatable setlocal traceback setfenv getinfo setupvalue getlocal getregistry getfenv io lines write close flush open output type read stderr stdin input stdout popen tmpfile math log max acos huge ldexp pi cos tanh pow deg tan cosh sinh random randomseed frexp ceil floor rad abs sqrt modf asin min mod fmod log10 atan2 exp sin atan os exit setlocale date getenv difftime remove time clock tmpname rename execute package preload loadlib loaded loaders cpath config path seeall string sub upper len gfind rep find match char dump gmatch reverse byte format gsub lower table setn insert getn foreachi maxn foreach concat sort remove";
fn list(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try scope.array();
    for (values, 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "lua", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const long = try scope.object();
    try scope.put(long, "begin", try scope.text(opening));
    try scope.put(long, "end", try scope.text(closing));
    try scope.put(long, "contains", try list(&scope, &.{try scope.text("self")}));
    const comments = try scope.array();
    const first_comment = try scope.get(hljs, "COMMENT");
    try scope.index(comments, 0, try scope.call(first_comment, hljs, &.{ try scope.text("--(?!" ++ opening ++ ")"), try scope.text("$") }));
    const second_comment = try scope.get(hljs, "COMMENT");
    const options = try scope.object();
    try scope.put(options, "contains", try list(&scope, &.{long}));
    try scope.put(options, "relevance", c.JS_NewInt32(engine.context, 10));
    try scope.index(comments, 1, try scope.call(second_comment, hljs, &.{ try scope.text("--" ++ opening), try scope.text(closing), options }));
    const language = try scope.object();
    try scope.put(language, "name", try scope.text("Lua"));
    const words = try scope.object();
    try scope.put(words, "$pattern", try scope.get(hljs, "UNDERSCORE_IDENT_RE"));
    try scope.put(words, "literal", try scope.text("true false nil"));
    try scope.put(words, "keyword", try scope.text("and break do else elseif end for goto if in local not or repeat return then until while"));
    try scope.put(words, "built_in", try scope.text(builtins));
    try scope.put(language, "keywords", words);
    // Read comments.concat before evaluating the argument-array's live hljs getters.
    const concat = try scope.get(comments, "concat");
    const alternatives = try scope.array();
    const function = try scope.object();
    try scope.put(function, "className", try scope.text("function"));
    try scope.put(function, "beginKeywords", try scope.text("function"));
    try scope.put(function, "end", try scope.text("\\)"));
    const inner = try scope.array();
    const inherit = try scope.get(hljs, "inherit");
    const title = try scope.get(hljs, "TITLE_MODE");
    const changes = try scope.object();
    try scope.put(changes, "begin", try scope.text("([_a-zA-Z]\\w*\\.)*([_a-zA-Z]\\w*:)?[_a-zA-Z]\\w*"));
    try scope.index(inner, 0, try scope.call(inherit, hljs, &.{ title, changes }));
    const params = try scope.object();
    try scope.put(params, "className", try scope.text("params"));
    try scope.put(params, "begin", try scope.text("\\("));
    try scope.put(params, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try scope.put(params, "contains", comments);
    try scope.index(inner, 1, params);
    try scope.put(function, "contains", try scope.invoke(inner, "concat", &.{comments}));
    try scope.index(alternatives, 0, function);
    try scope.index(alternatives, 1, try scope.get(hljs, "C_NUMBER_MODE"));
    try scope.index(alternatives, 2, try scope.get(hljs, "APOS_STRING_MODE"));
    try scope.index(alternatives, 3, try scope.get(hljs, "QUOTE_STRING_MODE"));
    const string = try scope.object();
    try scope.put(string, "className", try scope.text("string"));
    try scope.put(string, "begin", try scope.text(opening));
    try scope.put(string, "end", try scope.text(closing));
    try scope.put(string, "contains", try list(&scope, &.{long}));
    try scope.put(string, "relevance", c.JS_NewInt32(engine.context, 5));
    try scope.index(alternatives, 4, string);
    try scope.put(language, "contains", try scope.call(concat, comments, &.{alternatives}));
    return c.JS_DupValue(engine.context, language);
}
