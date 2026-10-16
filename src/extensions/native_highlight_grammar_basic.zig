//! Actual highlight.js10.7.3 BASIC factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "basic", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("BASIC"));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "illegal", try s.text("^."));
    const words = try s.object();
    try s.put(words, "$pattern", try s.text("[a-zA-Z][a-zA-Z0-9_$%!#]*"));
    try s.put(words, "keyword", try s.text("ABS ASC AND ATN AUTO|0 BEEP BLOAD|10 BSAVE|10 CALL CALLS CDBL CHAIN CHDIR CHR$|10 CINT CIRCLE CLEAR CLOSE CLS COLOR COM COMMON CONT COS CSNG CSRLIN CVD CVI CVS DATA DATE$ DEFDBL DEFINT DEFSNG DEFSTR DEF|0 SEG USR DELETE DIM DRAW EDIT END ENVIRON ENVIRON$ EOF EQV ERASE ERDEV ERDEV$ ERL ERR ERROR EXP FIELD FILES FIX FOR|0 FRE GET GOSUB|10 GOTO HEX$ IF THEN ELSE|0 INKEY$ INP INPUT INPUT# INPUT$ INSTR IMP INT IOCTL IOCTL$ KEY ON OFF LIST KILL LEFT$ LEN LET LINE LLIST LOAD LOC LOCATE LOF LOG LPRINT USING LSET MERGE MID$ MKDIR MKD$ MKI$ MKS$ MOD NAME NEW NEXT NOISE NOT OCT$ ON OR PEN PLAY STRIG OPEN OPTION BASE OUT PAINT PALETTE PCOPY PEEK PMAP POINT POKE POS PRINT PRINT] PSET PRESET PUT RANDOMIZE READ REM RENUM RESET|0 RESTORE RESUME RETURN|0 RIGHT$ RMDIR RND RSET RUN SAVE SCREEN SGN SHELL SIN SOUND SPACE$ SPC SQR STEP STICK STOP STR$ STRING$ SWAP SYSTEM TAB TAN TIME$ TIMER TROFF TRON TO USR VAL VARPTR VARPTR$ VIEW WAIT WHILE WEND WIDTH WINDOW WRITE XOR"));
    try s.put(language, "keywords", words);
    const contains = try b.list(&s, &.{try s.get(hljs, "QUOTE_STRING_MODE")});
    inline for (.{ .{ "REM", 10 }, .{ "'", 0 } }, 0..) |entry, index| {
        const comment = try s.get(hljs, "COMMENT");
        const options = try s.object();
        try s.put(options, "relevance", b.c.JS_NewInt32(e.context, entry[1]));
        try s.index(contains, @intCast(index + 1), try s.call(comment, hljs, &.{ try s.text(entry[0]), try s.text("$"), options }));
    }
    const line = try b.mode(&s, "symbol");
    try s.put(line, "begin", try s.text("^[0-9]+ "));
    try s.put(line, "relevance", b.c.JS_NewInt32(e.context, 10));
    try s.index(contains, 3, line);
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try s.text("\\b\\d+(\\.\\d+)?([edED]\\d+)?[#!]?"));
    try s.put(number, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(contains, 4, number);
    const hex = try b.mode(&s, "number");
    try s.put(hex, "begin", try s.text("(&[hH][0-9a-fA-F]{1,4})"));
    try s.index(contains, 5, hex);
    const octal = try b.mode(&s, "number");
    try s.put(octal, "begin", try s.text("(&[oO][0-7]{1,6})"));
    try s.index(contains, 6, octal);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
