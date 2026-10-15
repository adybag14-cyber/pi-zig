//! Actual highlight.js10.7.3 Packet Filter factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "pf", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const macro = try b.mode(&s, "variable");
    try s.put(macro, "begin", try b.rx(&s, "\\$[\\w\\d#@][\\w\\d_]*"));
    const table = try b.mode(&s, "variable");
    try s.put(table, "begin", try b.rx(&s, "<(?!\\/)"));
    try s.put(table, "end", try b.rx(&s, ">"));
    const language = try s.object();
    try s.put(language, "name", try s.text("Packet Filter config"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("pf.conf")}));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try b.rx(&s, "[a-z0-9_<>-]+"));
    try s.put(keywords, "built_in", try s.text("block match pass load anchor|5 antispoof|10 set table"));
    try s.put(keywords, "keyword", try s.text("in out log quick on rdomain inet inet6 proto from port os to route allow-opts divert-packet divert-reply divert-to flags group icmp-type icmp6-type label once probability recieved-on rtable prio queue tos tag tagged user keep fragment for os drop af-to|10 binat-to|10 nat-to|10 rdr-to|10 bitmask least-stats random round-robin source-hash static-port dup-to reply-to route-to parent bandwidth default min max qlimit block-policy debug fingerprints hostid limit loginterface optimization reassemble ruleset-optimization basic none profile skip state-defaults state-policy timeout const counters persist no modulate synproxy state|5 floating if-bound no-sync pflow|10 sloppy source-track global rule max-src-nodes max-src-states max-src-conn max-src-conn-rate overload flush scrub|5 max-mss min-ttl no-df|10 random-id"));
    try s.put(keywords, "literal", try s.text("all any no-route self urpf-failed egress|5 unknown"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ try s.get(hljs, "HASH_COMMENT_MODE"), try s.get(hljs, "NUMBER_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), macro, table }));
    return b.c.JS_DupValue(e.context, language);
}
