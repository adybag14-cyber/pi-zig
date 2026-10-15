//! Actual highlight.js10.7.3 static keyword inputs; factory body follows.
const source_keyword = "abs access after alias all and architecture array assert assume assume_guarantee attribute begin block body buffer bus case component configuration constant context cover disconnect downto default else elsif end entity exit fairness file for force function generate generic group guarded if impure in inertial inout is label library linkage literal loop map mod nand new next nor not null of on open or others out package parameter port postponed procedure process property protected pure range record register reject release rem report restrict restrict_guarantee return rol ror select sequence severity shared signal sla sll sra srl strong subtype then to transport type unaffected units until use variable view vmode vprop vunit wait when while with xnor xor";
const source_built_in = "boolean bit character integer time delay_length natural positive string bit_vector file_open_kind file_open_status std_logic std_logic_vector unsigned signed boolean_vector integer_vector std_ulogic std_ulogic_vector unresolved_unsigned u_unsigned unresolved_signed u_signed real_vector time_vector";
const source_literal = "false true note warning error failure line text side width";
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "vhdl", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("VHDL"));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    const kw = try s.object();
    try s.put(kw, "keyword", try s.text(source_keyword));
    try s.put(kw, "built_in", try s.text(source_built_in));
    try s.put(kw, "literal", try s.text(source_literal));
    try s.put(l, "keywords", kw);
    try s.put(l, "illegal", try b.rx(&s, "\\{"));
    const a = try b.list(&s, &.{try s.get(h, "C_BLOCK_COMMENT_MODE")});
    const f = try s.get(h, "COMMENT");
    const cb = try s.text("--");
    const ce = try s.text("$");
    try s.index(a, 1, try s.call(f, h, &.{ cb, ce }));
    try s.index(a, 2, try s.get(h, "QUOTE_STRING_MODE"));
    const num = try b.mode(&s, "number");
    try s.put(num, "begin", try s.text("\\b(\\d(_|\\d)*#\\w+(\\.\\w+)?#([eE][-+]?\\d(_|\\d)*)?|\\d(_|\\d)*(\\.\\d(_|\\d)*)?([eE][-+]?\\d(_|\\d)*)?)"));
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 3, num);
    const str = try b.mode(&s, "string");
    try s.put(str, "begin", try s.text("'(U|X|0|1|Z|W|L|H|-)'"));
    try s.put(str, "contains", try b.list(&s, &.{try s.get(h, "BACKSLASH_ESCAPE")}));
    try s.index(a, 4, str);
    const symbol = try b.mode(&s, "symbol");
    try s.put(symbol, "begin", try s.text("'[A-Za-z](_?[A-Za-z0-9])*"));
    try s.put(symbol, "contains", try b.list(&s, &.{try s.get(h, "BACKSLASH_ESCAPE")}));
    try s.index(a, 5, symbol);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
