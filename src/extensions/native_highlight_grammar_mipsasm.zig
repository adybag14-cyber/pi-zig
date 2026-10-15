//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "mipsasm", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("MIPS Assembly"));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("mips")}));
    const kw = try s.object();
    try s.put(kw, "$pattern", try s.concat(try s.text("\\.?"), try s.get(h, "IDENT_RE")));
    try s.put(kw, "meta", try s.text(source_meta));
    try s.put(kw, "built_in", try s.text(source_built_in));
    try s.put(l, "keywords", kw);
    const mnemonic = try b.mode(&s, "keyword");
    try s.put(mnemonic, "begin", try s.text("\\b(addi?u?|andi?|b(al)?|beql?|bgez(al)?l?|bgtzl?|blezl?|bltz(al)?l?|bnel?|cl[oz]|divu?|ext|ins|j(al)?|jalr(\\.hb)?|jr(\\.hb)?|lbu?|lhu?|ll|lui|lw[lr]?|maddu?|mfhi|mflo|movn|movz|move|msubu?|mthi|mtlo|mul|multu?|nop|nor|ori?|rotrv?|sb|sc|se[bh]|sh|sllv?|slti?u?|srav?|srlv?|subu?|sw[lr]?|xori?|wsbh|abs\\.[sd]|add\\.[sd]|alnv.ps|bc1[ft]l?|c\\.(s?f|un|u?eq|[ou]lt|[ou]le|ngle?|seq|l[et]|ng[et])\\.[sd]|(ceil|floor|round|trunc)\\.[lw]\\.[sd]|cfc1|cvt\\.d\\.[lsw]|cvt\\.l\\.[dsw]|cvt\\.ps\\.s|cvt\\.s\\.[dlw]|cvt\\.s\\.p[lu]|cvt\\.w\\.[dls]|div\\.[ds]|ldx?c1|luxc1|lwx?c1|madd\\.[sd]|mfc1|mov[fntz]?\\.[ds]|msub\\.[sd]|mth?c1|mul\\.[ds]|neg\\.[ds]|nmadd\\.[ds]|nmsub\\.[ds]|p[lu][lu]\\.ps|recip\\.fmt|r?sqrt\\.[ds]|sdx?c1|sub\\.[ds]|suxc1|swx?c1|break|cache|d?eret|[de]i|ehb|mfc0|mtc0|pause|prefx?|rdhwr|rdpgpr|sdbbp|ssnop|synci?|syscall|teqi?|tgei?u?|tlb(p|r|w[ir])|tlti?u?|tnei?|wait|wrpgpr)"));
    try s.put(mnemonic, "end", try s.text("\\s"));
    const a = try b.list(&s, &.{mnemonic});
    const cf = try s.get(h, "COMMENT");
    const cb = try s.text("[;#](?!\\s*$)");
    const ce = try s.text("$");
    try s.index(a, 1, try s.call(cf, h, &.{ cb, ce }));
    try s.index(a, 2, try s.get(h, "C_BLOCK_COMMENT_MODE"));
    try s.index(a, 3, try s.get(h, "QUOTE_STRING_MODE"));
    const str = try b.mode(&s, "string");
    try s.put(str, "begin", try s.text("'"));
    try s.put(str, "end", try s.text("[^\\\\]'"));
    try s.put(str, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 4, str);
    const title = try b.mode(&s, "title");
    try s.put(title, "begin", try s.text("\\|"));
    try s.put(title, "end", try s.text("\\|"));
    try s.put(title, "illegal", try s.text("\\n"));
    try s.put(title, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 5, title);
    const num = try b.mode(&s, "number");
    const nv = try s.array();
    for ([_][]const u8{ "0x[0-9a-f]+", "\\b-?\\d+" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        try s.index(nv, @intCast(i), m);
    }
    try s.put(num, "variants", nv);
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 6, num);
    const symbol = try b.mode(&s, "symbol");
    const sv = try s.array();
    for ([_][]const u8{ "^\\s*[a-z_\\.\\$][a-z0-9_\\.\\$]+:", "^\\s*[0-9]+:", "[0-9]+[bf]" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        try s.index(sv, @intCast(i), m);
    }
    try s.put(symbol, "variants", sv);
    try s.put(symbol, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 7, symbol);
    try s.put(l, "contains", a);
    try s.put(l, "illegal", try b.rx(&s, "/"));
    return b.c.JS_DupValue(e.context, l);
}
const source_meta = ".2byte .4byte .align .ascii .asciz .balign .byte .code .data .else .end .endif .endm .endr .equ .err .exitm .extern .global .hword .if .ifdef .ifndef .include .irp .long .macro .rept .req .section .set .skip .space .text .word .ltorg ";
const source_built_in = "$0 $1 $2 $3 $4 $5 $6 $7 $8 $9 $10 $11 $12 $13 $14 $15 $16 $17 $18 $19 $20 $21 $22 $23 $24 $25 $26 $27 $28 $29 $30 $31 zero at v0 v1 a0 a1 a2 a3 a4 a5 a6 a7 t0 t1 t2 t3 t4 t5 t6 t7 t8 t9 s0 s1 s2 s3 s4 s5 s6 s7 s8 k0 k1 gp sp fp ra $f0 $f1 $f2 $f2 $f4 $f5 $f6 $f7 $f8 $f9 $f10 $f11 $f12 $f13 $f14 $f15 $f16 $f17 $f18 $f19 $f20 $f21 $f22 $f23 $f24 $f25 $f26 $f27 $f28 $f29 $f30 $f31 Context Random EntryLo0 EntryLo1 Context PageMask Wired EntryHi HWREna BadVAddr Count Compare SR IntCtl SRSCtl SRSMap Cause EPC PRId EBase Config Config1 Config2 Config3 LLAddr Debug DEPC DESAVE CacheErr ECC ErrorEPC TagLo DataLo TagHi DataHi WatchLo WatchHi PerfCtl PerfCnt ";
