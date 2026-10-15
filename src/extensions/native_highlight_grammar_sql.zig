//! Actual highlight.js 10.7.3 SQL factory; source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const regex = @import("native_highlight_regex.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;

fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn words(s: *Scope, values: []const []const u8) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), try s.text(value));
    return result;
}
fn spreadInto(s: *Scope, array: c.JSValue, index: *u32, iterable: c.JSValue) !void {
    const symbol = try s.own(try s.engine.checked(JS_GetIteratorSymbol(s.engine.context)));
    var iterator = try js.Iterator.init(s.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try s.index(array, index.*, value);
        index.* += 1;
    }
}
fn spread(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const array = try s.array();
    var index: u32 = 0;
    try spreadInto(s, array, &index, iterable);
    return array;
}
fn filterKeyword(engine: *em.Engine, input: c.JSValue, functions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const contained = try s.invoke(functions, "includes", &.{input});
    return c.pi_js_bool(engine.context, @intFromBool(!s.truthy(contained)));
}
fn filterCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return filterKeyword(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn qualifies(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 4, try s.get(input, "length"), c.JS_NewInt32(engine.context, 3)));
}
fn qualifyCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return qualifies(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn reduceItem(engine: *em.Engine, input: c.JSValue, exceptions: c.JSValue, qualifier: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const matched = try s.invoke(input, "match", &.{try literal(&s, "\\|\\d+$")});
    if (s.truthy(matched) or s.truthy(try s.invoke(exceptions, "includes", &.{input}))) return c.JS_DupValue(engine.context, input);
    if (s.truthy(try s.call(qualifier, c.pi_js_undefined(), &.{input}))) return c.JS_DupValue(engine.context, try s.concat(try s.stringify(input), try s.text("|0")));
    return c.JS_DupValue(engine.context, input);
}
fn reduceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return reduceItem(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "sql", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const comment = try s.invoke(hljs, "COMMENT", &.{ try s.text("--"), try s.text("$") });
    const string = try s.object();
    try s.put(string, "className", try s.text("string"));
    const string_variant = try s.object();
    try s.put(string_variant, "begin", try literal(&s, "'"));
    try s.put(string_variant, "end", try literal(&s, "'"));
    const double_apos = try s.object();
    try s.put(double_apos, "begin", try literal(&s, "''"));
    try s.put(string_variant, "contains", try list(&s, &.{double_apos}));
    try s.put(string, "variants", try list(&s, &.{string_variant}));
    const quoted_identifier = try s.object();
    try s.put(quoted_identifier, "begin", try literal(&s, "\""));
    try s.put(quoted_identifier, "end", try literal(&s, "\""));
    const double_quote = try s.object();
    try s.put(double_quote, "begin", try literal(&s, "\"\""));
    try s.put(quoted_identifier, "contains", try list(&s, &.{double_quote}));
    const literal_words = try words(&s, &literals);
    const multi_types = try words(&s, &multi_word_types);
    const type_words = try words(&s, &types);
    const non_reserved = try words(&s, &non_reserved_words);
    const reserved = try words(&s, &reserved_words);
    const functions = try words(&s, &reserved_functions);
    const no_parens = try words(&s, &possible_without_parens);
    const combinations = try words(&s, &combos);
    const combined = try s.array();
    var keyword_index: u32 = 0;
    try spreadInto(&s, combined, &keyword_index, reserved);
    try spreadInto(&s, combined, &keyword_index, non_reserved);
    const filter = try s.get(combined, "filter");
    var filter_roots = [_]c.JSValue{functions};
    const filter_function = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, filterCallback, "", 1, 0, filter_roots.len, &filter_roots)));
    const keyword_words = try s.call(filter, combined, &.{filter_function});
    const variable = try s.object();
    try s.put(variable, "className", try s.text("variable"));
    try s.put(variable, "begin", try literal(&s, "@[a-z0-9]+"));
    const operator = try s.object();
    try s.put(operator, "className", try s.text("operator"));
    try s.put(operator, "begin", try literal(&s, "[-+*/=%^~]|&&?|\\|\\|?|!=?|<(?:=>?|<|>)?|>[>=]?"));
    try s.put(operator, "relevance", c.JS_NewInt32(engine.context, 0));
    const function_call = try s.object();
    const function_prefix = try literal(&s, "\\b");
    const function_alternatives = try s.own(try regex.either(engine, try spread(&s, functions)));
    try s.put(function_call, "begin", try s.own(try regex.concat(engine, try list(&s, &.{ function_prefix, function_alternatives, try literal(&s, "\\s*\\(") }))));
    const function_keywords = try s.object();
    try s.put(function_keywords, "built_in", functions);
    try s.put(function_call, "keywords", function_keywords);
    const language = try s.object();
    try s.put(language, "name", try s.text("SQL"));
    try s.put(language, "case_insensitive", c.pi_js_bool(engine.context, 1));
    try s.put(language, "illegal", try literal(&s, "[{}]|<\\/"));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try literal(&s, "\\b[\\w\\.]+"));
    const qualifier = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, qualifyCallback, "when", 1)));
    const exceptions = try s.array();
    const map = try s.get(keyword_words, "map");
    var reduce_roots = [_]c.JSValue{ exceptions, qualifier };
    const reduce_function = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, reduceCallback, "", 1, 0, reduce_roots.len, &reduce_roots)));
    try s.put(keywords, "keyword", try s.call(map, keyword_words, &.{reduce_function}));
    try s.put(keywords, "literal", literal_words);
    try s.put(keywords, "type", type_words);
    try s.put(keywords, "built_in", no_parens);
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    const combination = try s.object();
    try s.put(combination, "begin", try s.own(try regex.either(engine, try spread(&s, combinations))));
    const combination_keywords = try s.object();
    try s.put(combination_keywords, "$pattern", try literal(&s, "[\\w\\.]+"));
    try s.put(combination_keywords, "keyword", try s.invoke(keyword_words, "concat", &.{combinations}));
    try s.put(combination_keywords, "literal", literal_words);
    try s.put(combination_keywords, "type", type_words);
    try s.put(combination, "keywords", combination_keywords);
    try s.index(contains, 0, combination);
    const multi_type = try s.object();
    try s.put(multi_type, "className", try s.text("type"));
    try s.put(multi_type, "begin", try s.own(try regex.either(engine, try spread(&s, multi_types))));
    try s.index(contains, 1, multi_type);
    try s.index(contains, 2, function_call);
    try s.index(contains, 3, variable);
    try s.index(contains, 4, string);
    try s.index(contains, 5, quoted_identifier);
    try s.index(contains, 6, try s.get(hljs, "C_NUMBER_MODE"));
    try s.index(contains, 7, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try s.index(contains, 8, comment);
    try s.index(contains, 9, operator);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}

const literals = [_][]const u8{
    "true",
    "false",
    "unknown",
};
const multi_word_types = [_][]const u8{
    "double precision",
    "large object",
    "with timezone",
    "without timezone",
};
const types = [_][]const u8{
    "bigint",
    "binary",
    "blob",
    "boolean",
    "char",
    "character",
    "clob",
    "date",
    "dec",
    "decfloat",
    "decimal",
    "float",
    "int",
    "integer",
    "interval",
    "nchar",
    "nclob",
    "national",
    "numeric",
    "real",
    "row",
    "smallint",
    "time",
    "timestamp",
    "varchar",
    "varying",
    "varbinary",
};
const non_reserved_words = [_][]const u8{
    "add",
    "asc",
    "collation",
    "desc",
    "final",
    "first",
    "last",
    "view",
};
const reserved_words = [_][]const u8{
    "abs",
    "acos",
    "all",
    "allocate",
    "alter",
    "and",
    "any",
    "are",
    "array",
    "array_agg",
    "array_max_cardinality",
    "as",
    "asensitive",
    "asin",
    "asymmetric",
    "at",
    "atan",
    "atomic",
    "authorization",
    "avg",
    "begin",
    "begin_frame",
    "begin_partition",
    "between",
    "bigint",
    "binary",
    "blob",
    "boolean",
    "both",
    "by",
    "call",
    "called",
    "cardinality",
    "cascaded",
    "case",
    "cast",
    "ceil",
    "ceiling",
    "char",
    "char_length",
    "character",
    "character_length",
    "check",
    "classifier",
    "clob",
    "close",
    "coalesce",
    "collate",
    "collect",
    "column",
    "commit",
    "condition",
    "connect",
    "constraint",
    "contains",
    "convert",
    "copy",
    "corr",
    "corresponding",
    "cos",
    "cosh",
    "count",
    "covar_pop",
    "covar_samp",
    "create",
    "cross",
    "cube",
    "cume_dist",
    "current",
    "current_catalog",
    "current_date",
    "current_default_transform_group",
    "current_path",
    "current_role",
    "current_row",
    "current_schema",
    "current_time",
    "current_timestamp",
    "current_path",
    "current_role",
    "current_transform_group_for_type",
    "current_user",
    "cursor",
    "cycle",
    "date",
    "day",
    "deallocate",
    "dec",
    "decimal",
    "decfloat",
    "declare",
    "default",
    "define",
    "delete",
    "dense_rank",
    "deref",
    "describe",
    "deterministic",
    "disconnect",
    "distinct",
    "double",
    "drop",
    "dynamic",
    "each",
    "element",
    "else",
    "empty",
    "end",
    "end_frame",
    "end_partition",
    "end-exec",
    "equals",
    "escape",
    "every",
    "except",
    "exec",
    "execute",
    "exists",
    "exp",
    "external",
    "extract",
    "false",
    "fetch",
    "filter",
    "first_value",
    "float",
    "floor",
    "for",
    "foreign",
    "frame_row",
    "free",
    "from",
    "full",
    "function",
    "fusion",
    "get",
    "global",
    "grant",
    "group",
    "grouping",
    "groups",
    "having",
    "hold",
    "hour",
    "identity",
    "in",
    "indicator",
    "initial",
    "inner",
    "inout",
    "insensitive",
    "insert",
    "int",
    "integer",
    "intersect",
    "intersection",
    "interval",
    "into",
    "is",
    "join",
    "json_array",
    "json_arrayagg",
    "json_exists",
    "json_object",
    "json_objectagg",
    "json_query",
    "json_table",
    "json_table_primitive",
    "json_value",
    "lag",
    "language",
    "large",
    "last_value",
    "lateral",
    "lead",
    "leading",
    "left",
    "like",
    "like_regex",
    "listagg",
    "ln",
    "local",
    "localtime",
    "localtimestamp",
    "log",
    "log10",
    "lower",
    "match",
    "match_number",
    "match_recognize",
    "matches",
    "max",
    "member",
    "merge",
    "method",
    "min",
    "minute",
    "mod",
    "modifies",
    "module",
    "month",
    "multiset",
    "national",
    "natural",
    "nchar",
    "nclob",
    "new",
    "no",
    "none",
    "normalize",
    "not",
    "nth_value",
    "ntile",
    "null",
    "nullif",
    "numeric",
    "octet_length",
    "occurrences_regex",
    "of",
    "offset",
    "old",
    "omit",
    "on",
    "one",
    "only",
    "open",
    "or",
    "order",
    "out",
    "outer",
    "over",
    "overlaps",
    "overlay",
    "parameter",
    "partition",
    "pattern",
    "per",
    "percent",
    "percent_rank",
    "percentile_cont",
    "percentile_disc",
    "period",
    "portion",
    "position",
    "position_regex",
    "power",
    "precedes",
    "precision",
    "prepare",
    "primary",
    "procedure",
    "ptf",
    "range",
    "rank",
    "reads",
    "real",
    "recursive",
    "ref",
    "references",
    "referencing",
    "regr_avgx",
    "regr_avgy",
    "regr_count",
    "regr_intercept",
    "regr_r2",
    "regr_slope",
    "regr_sxx",
    "regr_sxy",
    "regr_syy",
    "release",
    "result",
    "return",
    "returns",
    "revoke",
    "right",
    "rollback",
    "rollup",
    "row",
    "row_number",
    "rows",
    "running",
    "savepoint",
    "scope",
    "scroll",
    "search",
    "second",
    "seek",
    "select",
    "sensitive",
    "session_user",
    "set",
    "show",
    "similar",
    "sin",
    "sinh",
    "skip",
    "smallint",
    "some",
    "specific",
    "specifictype",
    "sql",
    "sqlexception",
    "sqlstate",
    "sqlwarning",
    "sqrt",
    "start",
    "static",
    "stddev_pop",
    "stddev_samp",
    "submultiset",
    "subset",
    "substring",
    "substring_regex",
    "succeeds",
    "sum",
    "symmetric",
    "system",
    "system_time",
    "system_user",
    "table",
    "tablesample",
    "tan",
    "tanh",
    "then",
    "time",
    "timestamp",
    "timezone_hour",
    "timezone_minute",
    "to",
    "trailing",
    "translate",
    "translate_regex",
    "translation",
    "treat",
    "trigger",
    "trim",
    "trim_array",
    "true",
    "truncate",
    "uescape",
    "union",
    "unique",
    "unknown",
    "unnest",
    "update   ",
    "upper",
    "user",
    "using",
    "value",
    "values",
    "value_of",
    "var_pop",
    "var_samp",
    "varbinary",
    "varchar",
    "varying",
    "versioning",
    "when",
    "whenever",
    "where",
    "width_bucket",
    "window",
    "with",
    "within",
    "without",
    "year",
};
const reserved_functions = [_][]const u8{
    "abs",
    "acos",
    "array_agg",
    "asin",
    "atan",
    "avg",
    "cast",
    "ceil",
    "ceiling",
    "coalesce",
    "corr",
    "cos",
    "cosh",
    "count",
    "covar_pop",
    "covar_samp",
    "cume_dist",
    "dense_rank",
    "deref",
    "element",
    "exp",
    "extract",
    "first_value",
    "floor",
    "json_array",
    "json_arrayagg",
    "json_exists",
    "json_object",
    "json_objectagg",
    "json_query",
    "json_table",
    "json_table_primitive",
    "json_value",
    "lag",
    "last_value",
    "lead",
    "listagg",
    "ln",
    "log",
    "log10",
    "lower",
    "max",
    "min",
    "mod",
    "nth_value",
    "ntile",
    "nullif",
    "percent_rank",
    "percentile_cont",
    "percentile_disc",
    "position",
    "position_regex",
    "power",
    "rank",
    "regr_avgx",
    "regr_avgy",
    "regr_count",
    "regr_intercept",
    "regr_r2",
    "regr_slope",
    "regr_sxx",
    "regr_sxy",
    "regr_syy",
    "row_number",
    "sin",
    "sinh",
    "sqrt",
    "stddev_pop",
    "stddev_samp",
    "substring",
    "substring_regex",
    "sum",
    "tan",
    "tanh",
    "translate",
    "translate_regex",
    "treat",
    "trim",
    "trim_array",
    "unnest",
    "upper",
    "value_of",
    "var_pop",
    "var_samp",
    "width_bucket",
};
const possible_without_parens = [_][]const u8{
    "current_catalog",
    "current_date",
    "current_default_transform_group",
    "current_path",
    "current_role",
    "current_schema",
    "current_transform_group_for_type",
    "current_user",
    "session_user",
    "system_time",
    "system_user",
    "current_time",
    "localtime",
    "current_timestamp",
    "localtimestamp",
};
const combos = [_][]const u8{
    "create table",
    "insert into",
    "primary key",
    "foreign key",
    "not null",
    "alter table",
    "add constraint",
    "grouping sets",
    "on overflow",
    "character set",
    "respect nulls",
    "ignore nulls",
    "nulls first",
    "nulls last",
    "depth first",
    "breadth first",
};
