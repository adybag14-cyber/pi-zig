//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "n1ql", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("N1QL"));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    const statement = try s.object();
    try s.put(statement, "beginKeywords", try s.text("build create index delete drop explain infer|10 insert merge prepare select update upsert|10"));
    try s.put(statement, "end", try b.rx(&s, ";"));
    try s.put(statement, "endsWithParent", b.boolean(&s, true));
    const kw = try s.object();
    try s.put(kw, "keyword", try s.text(source_keyword));
    try s.put(kw, "literal", try s.text(source_literal));
    try s.put(kw, "built_in", try s.text(source_built_in));
    try s.put(statement, "keywords", kw);
    const a = try s.array();
    for ([_][]const u8{ "'", "\"", "`" }, 0..) |p, i| {
        const m = try b.mode(&s, if (i == 2) "symbol" else "string");
        try s.put(m, "begin", try s.text(p));
        try s.put(m, "end", try s.text(p));
        try s.put(m, "contains", try b.list(&s, &.{try s.get(h, "BACKSLASH_ESCAPE")}));
        if (i == 2) try s.put(m, "relevance", b.c.JS_NewInt32(e.context, 2));
        try s.index(a, @intCast(i), m);
    }
    try s.index(a, 3, try s.get(h, "C_NUMBER_MODE"));
    try s.index(a, 4, try s.get(h, "C_BLOCK_COMMENT_MODE"));
    try s.put(statement, "contains", a);
    try s.put(l, "contains", try b.list(&s, &.{ statement, try s.get(h, "C_BLOCK_COMMENT_MODE") }));
    return b.c.JS_DupValue(e.context, l);
}
const source_keyword = "all alter analyze and any array as asc begin between binary boolean break bucket build by call case cast cluster collate collection commit connect continue correlate cover create database dataset datastore declare decrement delete derived desc describe distinct do drop each element else end every except exclude execute exists explain fetch first flatten for force from function grant group gsi having if ignore ilike in include increment index infer inline inner insert intersect into is join key keys keyspace known last left let letting like limit lsm map mapping matched materialized merge minus namespace nest not number object offset on option or order outer over parse partition password path pool prepare primary private privilege procedure public raw realm reduce rename return returning revoke right role rollback satisfies schema select self semi set show some start statistics string system then to transaction trigger truncate under union unique unknown unnest unset update upsert use user using validate value valued values via view when where while with within work xor";
const source_literal = "true false null missing|5";
const source_built_in = "array_agg array_append array_concat array_contains array_count array_distinct array_ifnull array_length array_max array_min array_position array_prepend array_put array_range array_remove array_repeat array_replace array_reverse array_sort array_sum avg count max min sum greatest least ifmissing ifmissingornull ifnull missingif nullif ifinf ifnan ifnanorinf naninf neginfif posinfif clock_millis clock_str date_add_millis date_add_str date_diff_millis date_diff_str date_part_millis date_part_str date_trunc_millis date_trunc_str duration_to_str millis str_to_millis millis_to_str millis_to_utc millis_to_zone_name now_millis now_str str_to_duration str_to_utc str_to_zone_name decode_json encode_json encoded_size poly_length base64 base64_encode base64_decode meta uuid abs acos asin atan atan2 ceil cos degrees e exp ln log floor pi power radians random round sign sin sqrt tan trunc object_length object_names object_pairs object_inner_pairs object_values object_inner_values object_add object_put object_remove object_unwrap regexp_contains regexp_like regexp_position regexp_replace contains initcap length lower ltrim position repeat replace rtrim split substr title trim upper isarray isatom isboolean isnumber isobject isstring type toarray toatom toboolean tonumber toobject tostring";
