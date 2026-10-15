//! Complete Source highlight.js10.7.3 Perl factory; source-only draft.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const keywords_text = "abs accept alarm and atan2 bind binmode bless break caller chdir chmod chomp chop chown chr chroot close closedir connect continue cos crypt dbmclose dbmopen defined delete die do dump each else elsif endgrent endhostent endnetent endprotoent endpwent endservent eof eval exec exists exit exp fcntl fileno flock for foreach fork format formline getc getgrent getgrgid getgrnam gethostbyaddr gethostbyname gethostent getlogin getnetbyaddr getnetbyname getnetent getpeername getpgrp getpriority getprotobyname getprotobynumber getprotoent getpwent getpwnam getpwuid getservbyname getservbyport getservent getsockname getsockopt given glob gmtime goto grep gt hex if index int ioctl join keys kill last lc lcfirst length link listen local localtime log lstat lt ma map mkdir msgctl msgget msgrcv msgsnd my ne next no not oct open opendir or ord our pack package pipe pop pos print printf prototype push q|0 qq quotemeta qw qx rand read readdir readline readlink readpipe recv redo ref rename require reset return reverse rewinddir rindex rmdir say scalar seek seekdir select semctl semget semop send setgrent sethostent setnetent setpgrp setpriority setprotoent setpwent setservent setsockopt shift shmctl shmget shmread shmwrite shutdown sin sleep socket socketpair sort splice split sprintf sqrt srand stat state study sub substr symlink syscall sysopen sysread sysseek system syswrite tell telldir tie tied time times tr truncate uc ucfirst umask undef unless unlink unpack unshift untie until use utime values vec wait waitpid wantarray warn when while write x|0 xor y|0";
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn words(s: *Scope, text: []const u8) !c.JSValue {
    const result = try s.array();
    var parts = std.mem.splitScalar(u8, text, ' ');
    var index: u32 = 0;
    while (parts.next()) |part| : (index += 1) try s.index(result, index, try s.text(part));
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
fn joined(s: *Scope, args: []const c.JSValue, separator: []const u8) !c.JSValue {
    const values = try list(s, args);
    const fn_value = try s.own(try s.engine.checked(c.JS_NewCFunction(s.engine.context, sourceCallback, "", 1)));
    return s.invoke(try s.invoke(values, "map", &.{fn_value}), "join", &.{try s.text(separator)});
}
fn concat(s: *Scope, args: []const c.JSValue) !c.JSValue {
    return joined(s, args, "");
}
fn either(s: *Scope, delimiters: c.JSValue) !c.JSValue {
    const spread = try s.own(try @import("native_sdk_transcript_replay.zig").arraySpread(s.engine, delimiters, null));
    const count = try @import("native_sdk.zig").length(s.engine, spread);
    const args = try s.engine.gpa.alloc(c.JSValue, count);
    defer s.engine.gpa.free(args);
    for (args, 0..) |*slot, index| slot.* = try s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, spread, @intCast(index))));
    return s.concat(try s.concat(try s.text("("), try joined(s, args, "|")), try s.text(")"));
}
fn paired(s: *Scope, prefix: c.JSValue, open: c.JSValue, close: c.JSValue, modifiers: c.JSValue, double: bool) !c.JSValue {
    const middle = if (double) if (s.equal(close, try s.text("\\1"))) close else try concat(s, &.{ close, open }) else c.pi_js_undefined();
    const group = try concat(s, &.{ try s.text("(?:"), prefix, try s.text(")") });
    const inner = try literal(s, "(?:\\\\.|[^\\\\/])*?");
    return concat(s, if (double) &.{ group, open, inner, middle, try literal(s, "(?:\\\\.|[^\\\\/])*?"), close, modifiers } else &.{ group, open, inner, close, modifiers });
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "perl", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const keyword_values = try words(&s, keywords_text);
    const modifiers = try literal(&s, "[dualxmsipngr]{0,12}");
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try literal(&s, "[\\w.]+"));
    try s.put(keywords, "keyword", try s.invoke(keyword_values, "join", &.{try s.text(" ")}));
    const subst = try mode(&s, "subst");
    try s.put(subst, "begin", try s.text("[$@]\\{"));
    try s.put(subst, "end", try s.text("\\}"));
    try s.put(subst, "keywords", keywords);
    const method = try s.object();
    try s.put(method, "begin", try literal(&s, "->\\{"));
    try s.put(method, "end", try literal(&s, "\\}"));
    const variable = try s.object();
    const variables = try s.array();
    const digit = try s.object();
    try s.put(digit, "begin", try literal(&s, "\\$\\d"));
    try s.index(variables, 0, digit);
    const named = try s.object();
    try s.put(named, "begin", try concat(&s, &.{ try literal(&s, "[$%@](\\^\\w\\b|#\\w+(::\\w+)*|\\{\\w+\\}|\\w+(::\\w*)*)"), try s.text("(?![A-Za-z])(?![@$%])") }));
    try s.index(variables, 1, named);
    const special = try s.object();
    try s.put(special, "begin", try literal(&s, "[$%@][^\\s\\w{]"));
    try s.put(special, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(variables, 2, special);
    try s.put(variable, "variants", variables);
    const string_contains = try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst, variable });
    const delimiters = try s.array();
    inline for (.{ "!", "/", "\\|", "\\?", "'", "\"", "#" }, 0..) |pattern, index| try s.index(delimiters, index, try literal(&s, pattern));
    const defaults = try s.array();
    try s.index(defaults, 0, variable);
    try s.index(defaults, 1, try s.get(hljs, "HASH_COMMENT_MODE"));
    const comment = try s.get(hljs, "COMMENT");
    const comment_begin = try literal(&s, "^=\\w");
    const comment_end = try literal(&s, "=cut");
    const comment_options = try s.object();
    try s.put(comment_options, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.index(defaults, 2, try s.call(comment, hljs, &.{ comment_begin, comment_end, comment_options }));
    try s.index(defaults, 3, method);
    const string = try mode(&s, "string");
    try s.put(string, "contains", string_contains);
    const strings = try s.array();
    inline for (.{ .{ "q[qwxr]?\\s*\\(", "\\)" }, .{ "q[qwxr]?\\s*\\[", "\\]" }, .{ "q[qwxr]?\\s*\\{", "\\}" }, .{ "q[qwxr]?\\s*\\|", "\\|" }, .{ "q[qwxr]?\\s*<", ">" }, .{ "qw\\s+q", "q" } }, 0..) |entry, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(entry[0]));
        try s.put(variant, "end", try s.text(entry[1]));
        try s.put(variant, "relevance", c.JS_NewInt32(engine.context, 5));
        try s.index(strings, index, variant);
    }
    inline for (.{ "'", "\"", "`" }, 0..) |delimiter, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(delimiter));
        try s.put(variant, "end", try s.text(delimiter));
        if (index != 1) try s.put(variant, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
        try s.index(strings, index + 6, variant);
    }
    const word_braces = try s.object();
    try s.put(word_braces, "begin", try literal(&s, "\\{\\w+\\}"));
    try s.put(word_braces, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(strings, 9, word_braces);
    const fat_arrow = try s.object();
    try s.put(fat_arrow, "begin", try s.text("-?\\w+\\s*=>"));
    try s.put(fat_arrow, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(strings, 10, fat_arrow);
    try s.put(string, "variants", strings);
    try s.index(defaults, 4, string);
    const number = try mode(&s, "number");
    try s.put(number, "begin", try s.text("(\\b0[0-7_]+)|(\\b0x[0-9a-fA-F_]+)|(\\b[1-9][0-9_]*(\\.[0-9_]+)?)|[0_]\\b"));
    try s.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(defaults, 5, number);
    const regex_container = try s.object();
    try s.put(regex_container, "begin", try s.concat(try s.concat(try s.text("(\\/\\/|"), try s.get(hljs, "RE_STARTERS_RE")), try s.text("|\\b(split|return|print|reverse|grep)\\b)\\s*")));
    try s.put(regex_container, "keywords", try s.text("split return print reverse grep"));
    try s.put(regex_container, "relevance", c.JS_NewInt32(engine.context, 0));
    const regexes = try s.array();
    try s.index(regexes, 0, try s.get(hljs, "HASH_COMMENT_MODE"));
    const double_regex = try mode(&s, "regexp");
    const doubles = try s.array();
    const common_double = try s.object();
    try s.put(common_double, "begin", try paired(&s, try s.text("s|tr|y"), try either(&s, delimiters), try s.text("\\1"), modifiers, true));
    try s.index(doubles, 0, common_double);
    inline for (.{ .{ "\\(", "\\)" }, .{ "\\[", "\\]" }, .{ "\\{", "\\}" } }, 0..) |entry, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try paired(&s, try s.text("s|tr|y"), try s.text(entry[0]), try s.text(entry[1]), modifiers, true));
        try s.index(doubles, index + 1, variant);
    }
    try s.put(double_regex, "variants", doubles);
    try s.put(double_regex, "relevance", c.JS_NewInt32(engine.context, 2));
    try s.index(regexes, 1, double_regex);
    const regex = try mode(&s, "regexp");
    const variants = try s.array();
    const empty_regex = try s.object();
    try s.put(empty_regex, "begin", try literal(&s, "(m|qr)//"));
    try s.put(empty_regex, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(variants, 0, empty_regex);
    const slash = try s.object();
    try s.put(slash, "begin", try paired(&s, try s.text("(?:m|qr)?"), try literal(&s, "/"), try literal(&s, "/"), modifiers, false));
    try s.index(variants, 1, slash);
    const common = try s.object();
    try s.put(common, "begin", try paired(&s, try s.text("m|qr"), try either(&s, delimiters), try literal(&s, "\\1"), modifiers, false));
    try s.index(variants, 2, common);
    inline for (.{ .{ "\\(", "\\)" }, .{ "\\[", "\\]" }, .{ "\\{", "\\}" } }, 0..) |entry, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try paired(&s, try s.text("m|qr"), try literal(&s, entry[0]), try literal(&s, entry[1]), modifiers, false));
        try s.index(variants, index + 3, variant);
    }
    try s.put(regex, "variants", variants);
    try s.index(regexes, 2, regex);
    try s.put(regex_container, "contains", regexes);
    try s.index(defaults, 6, regex_container);
    const function = try mode(&s, "function");
    try s.put(function, "beginKeywords", try s.text("sub"));
    try s.put(function, "end", try s.text("(\\s*\\(.*?\\))?[;{]"));
    try s.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(function, "relevance", c.JS_NewInt32(engine.context, 5));
    try s.put(function, "contains", try list(&s, &.{try s.get(hljs, "TITLE_MODE")}));
    try s.index(defaults, 7, function);
    const option = try s.object();
    try s.put(option, "begin", try s.text("-\\w\\b"));
    try s.put(option, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(defaults, 8, option);
    const data = try s.object();
    try s.put(data, "begin", try s.text("^__DATA__$"));
    try s.put(data, "end", try s.text("^__END__$"));
    try s.put(data, "subLanguage", try s.text("mojolicious"));
    const data_comment = try s.object();
    try s.put(data_comment, "begin", try s.text("^@@.*"));
    try s.put(data_comment, "end", try s.text("$"));
    try s.put(data_comment, "className", try s.text("comment"));
    try s.put(data, "contains", try list(&s, &.{data_comment}));
    try s.index(defaults, 9, data);
    try s.set(subst, "contains", defaults);
    try s.set(method, "contains", defaults);
    const language = try s.object();
    try s.put(language, "name", try s.text("Perl"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("pl"), try s.text("pm") }));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", defaults);
    return c.JS_DupValue(engine.context, language);
}
