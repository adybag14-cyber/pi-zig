//! Actual highlight.js10.7.3 Q factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "q", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try b.rx(&s, "(`?)[A-Za-z0-9_]+\\b"));
    try s.put(keywords, "keyword", try s.text("do while select delete by update from"));
    try s.put(keywords, "literal", try s.text("0b 1b"));
    try s.put(keywords, "built_in", try s.text("neg not null string reciprocal floor ceiling signum mod xbar xlog and or each scan over prior mmu lsq inv md5 ltime gtime count first var dev med cov cor all any rand sums prds mins maxs fills deltas ratios avgs differ prev next rank reverse iasc idesc asc desc msum mcount mavg mdev xrank mmin mmax xprev rotate distinct group where flip type key til get value attr cut set upsert raze union inter except cross sv vs sublist enlist read0 read1 hopen hclose hdel hsym hcount peach system ltrim rtrim trim lower upper ssr view tables views cols xcols keys xkey xcol xasc xdesc fkeys meta lj aj aj0 ij pj asof uj ww wj wj1 fby xgroup ungroup ej save load rsave rload show csv parse eval min max avg wavg wsum sin cos tan sum"));
    try s.put(keywords, "type", try s.text("`float `double int `timestamp `timespan `datetime `time `boolean `symbol `char `byte `short `long `real `month `date `minute `second `guid"));
    const language = try s.object();
    try s.put(language, "name", try s.text("Q"));
    try s.put(language, "aliases", try b.list(&s, &.{ try s.text("k"), try s.text("kdb") }));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), try s.get(hljs, "C_NUMBER_MODE") }));
    return b.c.JS_DupValue(e.context, language);
}
