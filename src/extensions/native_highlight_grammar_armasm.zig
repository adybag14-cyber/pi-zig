//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "armasm", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const comment = try s.object();
    const variants = try s.array();
    const f1 = try s.get(h, "COMMENT");
    const b1 = try s.text("^[ \\t]*(?=#)");
    const e1 = try s.text("$");
    const o1 = try s.object();
    try s.put(o1, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(o1, "excludeBegin", b.boolean(&s, true));
    try s.index(variants, 0, try s.call(f1, h, &.{ b1, e1, o1 }));
    const f2 = try s.get(h, "COMMENT");
    const b2 = try s.text("[;@]");
    const e2 = try s.text("$");
    const o2 = try s.object();
    try s.put(o2, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(variants, 1, try s.call(f2, h, &.{ b2, e2, o2 }));
    try s.index(variants, 2, try s.get(h, "C_LINE_COMMENT_MODE"));
    try s.index(variants, 3, try s.get(h, "C_BLOCK_COMMENT_MODE"));
    try s.put(comment, "variants", variants);
    const l = try s.object();
    try s.put(l, "name", try s.text("ARM Assembly"));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("arm")}));
    const kw = try s.object();
    try s.put(kw, "$pattern", try s.concat(try s.text("\\.?"), try s.get(h, "IDENT_RE")));
    try s.put(kw, "meta", try s.text(source_meta));
    try s.put(kw, "built_in", try s.text(source_built_in));
    try s.put(l, "keywords", kw);
    const mnemonic = try b.mode(&s, "keyword");
    try s.put(mnemonic, "begin", try s.text(source_mnemonic));
    const a = try b.list(&s, &.{ mnemonic, comment, try s.get(h, "QUOTE_STRING_MODE") });
    const str = try b.mode(&s, "string");
    try s.put(str, "begin", try s.text("'"));
    try s.put(str, "end", try s.text("[^\\\\]'"));
    try s.put(str, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 3, str);
    const title = try b.mode(&s, "title");
    try s.put(title, "begin", try s.text("\\|"));
    try s.put(title, "end", try s.text("\\|"));
    try s.put(title, "illegal", try s.text("\\n"));
    try s.put(title, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 4, title);
    const num = try b.mode(&s, "number");
    const nv = try s.array();
    for ([_][]const u8{ "[#$=]?0x[0-9a-f]+", "[#$=]?0b[01]+", "[#$=]\\d+", "\\b\\d+" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        try s.index(nv, @intCast(i), m);
    }
    try s.put(num, "variants", nv);
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 5, num);
    const symbol = try b.mode(&s, "symbol");
    const sv = try s.array();
    for ([_][]const u8{ "^[ \\t]*[a-z_\\.\\$][a-z0-9_\\.\\$]+:", "^[a-z_\\.\\$][a-z0-9_\\.\\$]+", "[=#]\\w+" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        try s.index(sv, @intCast(i), m);
    }
    try s.put(symbol, "variants", sv);
    try s.put(symbol, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 6, symbol);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_meta = ".2byte .4byte .align .ascii .asciz .balign .byte .code .data .else .end .endif .endm .endr .equ .err .exitm .extern .global .hword .if .ifdef .ifndef .include .irp .long .macro .rept .req .section .set .skip .space .text .word .arm .thumb .code16 .code32 .force_thumb .thumb_func .ltorg ALIAS ALIGN ARM AREA ASSERT ATTR CN CODE CODE16 CODE32 COMMON CP DATA DCB DCD DCDU DCDO DCFD DCFDU DCI DCQ DCQU DCW DCWU DN ELIF ELSE END ENDFUNC ENDIF ENDP ENTRY EQU EXPORT EXPORTAS EXTERN FIELD FILL FUNCTION GBLA GBLL GBLS GET GLOBAL IF IMPORT INCBIN INCLUDE INFO KEEP LCLA LCLL LCLS LTORG MACRO MAP MEND MEXIT NOFP OPT PRESERVE8 PROC QN READONLY RELOC REQUIRE REQUIRE8 RLIST FN ROUT SETA SETL SETS SN SPACE SUBT THUMB THUMBX TTL WHILE WEND ";
const source_built_in = "r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12 r13 r14 r15 pc lr sp ip sl sb fp a1 a2 a3 a4 v1 v2 v3 v4 v5 v6 v7 v8 f0 f1 f2 f3 f4 f5 f6 f7 p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13 p14 p15 c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 q0 q1 q2 q3 q4 q5 q6 q7 q8 q9 q10 q11 q12 q13 q14 q15 cpsr_c cpsr_x cpsr_s cpsr_f cpsr_cx cpsr_cxs cpsr_xs cpsr_xsf cpsr_sf cpsr_cxsf spsr_c spsr_x spsr_s spsr_f spsr_cx spsr_cxs spsr_xs spsr_xsf spsr_sf spsr_cxsf s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 s16 s17 s18 s19 s20 s21 s22 s23 s24 s25 s26 s27 s28 s29 s30 s31 d0 d1 d2 d3 d4 d5 d6 d7 d8 d9 d10 d11 d12 d13 d14 d15 d16 d17 d18 d19 d20 d21 d22 d23 d24 d25 d26 d27 d28 d29 d30 d31 {PC} {VAR} {TRUE} {FALSE} {OPT} {CONFIG} {ENDIAN} {CODESIZE} {CPU} {FPU} {ARCHITECTURE} {PCSTOREOFFSET} {ARMASM_VERSION} {INTER} {ROPI} {RWPI} {SWST} {NOSWST} . @";
const source_mnemonic = "\\b(adc|(qd?|sh?|u[qh]?)?add(8|16)?|usada?8|(q|sh?|u[qh]?)?(as|sa)x|and|adrl?|sbc|rs[bc]|asr|b[lx]?|blx|bxj|cbn?z|tb[bh]|bic|bfc|bfi|[su]bfx|bkpt|cdp2?|clz|clrex|cmp|cmn|cpsi[ed]|cps|setend|dbg|dmb|dsb|eor|isb|it[te]{0,3}|lsl|lsr|ror|rrx|ldm(([id][ab])|f[ds])?|ldr((s|ex)?[bhd])?|movt?|mvn|mra|mar|mul|[us]mull|smul[bwt][bt]|smu[as]d|smmul|smmla|mla|umlaal|smlal?([wbt][bt]|d)|mls|smlsl?[ds]|smc|svc|sev|mia([bt]{2}|ph)?|mrr?c2?|mcrr2?|mrs|msr|orr|orn|pkh(tb|bt)|rbit|rev(16|sh)?|sel|[su]sat(16)?|nop|pop|push|rfe([id][ab])?|stm([id][ab])?|str(ex)?[bhd]?|(qd?)?sub|(sh?|q|u[qh]?)?sub(8|16)|[su]xt(a?h|a?b(16)?)|srs([id][ab])?|swpb?|swi|smi|tst|teq|wfe|wfi|yield)(eq|ne|cs|cc|mi|pl|vs|vc|hi|ls|ge|lt|gt|le|al|hs|lo)?[sptrx]?(?=\\s)";
