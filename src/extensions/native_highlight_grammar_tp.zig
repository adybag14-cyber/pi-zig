//! Actual highlight.js 10.7.3 TP factory; source-only, unqualified.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "tp", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const id = try b.mode(&s, "number");
    try s.put(id, "begin", try s.text("[1-9][0-9]*"));
    try s.put(id, "relevance", b.c.JS_NewInt32(e.context, 0));
    const label = try b.mode(&s, "symbol");
    try s.put(label, "begin", try s.text(":[^\\]]+"));
    const data = try b.mode(&s, "built_in");
    try s.put(data, "begin", try s.text("(AR|P|PAYLOAD|PR|R|SR|RSR|LBL|VR|UALM|MESSAGE|UTOOL|UFRAME|TIMER|TIMER_OVERFLOW|JOINT_MAX_SPEED|RESUME_PROG|DIAG_REC)\\["));
    try s.put(data, "end", try s.text("\\]"));
    try s.put(data, "contains", try b.list(&s, &.{ try s.text("self"), id, label }));
    const io = try b.mode(&s, "built_in");
    try s.put(io, "begin", try s.text("(AI|AO|DI|DO|F|RI|RO|UI|UO|GI|GO|SI|SO)\\["));
    try s.put(io, "end", try s.text("\\]"));
    try s.put(io, "contains", try b.list(&s, &.{ try s.text("self"), id, try s.get(h, "QUOTE_STRING_MODE"), label }));
    const lang = try s.object();
    try s.put(lang, "name", try s.text("TP"));
    const kw = try s.object();
    try s.put(kw, "keyword", try s.text("ABORT ACC ADJUST AND AP_LD BREAK CALL CNT COL CONDITION CONFIG DA DB DIV DETECT ELSE END ENDFOR ERR_NUM ERROR_PROG FINE FOR GP GUARD INC IF JMP LINEAR_MAX_SPEED LOCK MOD MONITOR OFFSET Offset OR OVERRIDE PAUSE PREG PTH RT_LD RUN SELECT SKIP Skip TA TB TO TOOL_OFFSET Tool_Offset UF UT UFRAME_NUM UTOOL_NUM UNLOCK WAIT X Y Z W P R STRLEN SUBSTR FINDSTR VOFFSET PROG ATTR MN POS"));
    try s.put(kw, "literal", try s.text("ON OFF max_speed LPOS JPOS ENABLE DISABLE START STOP RESET"));
    try s.put(lang, "keywords", kw);
    const a = try b.list(&s, &.{ data, io });
    for ([_][]const u8{ "/(PROG|ATTR|MN|POS|END)\\b", "(CALL|RUN|POINT_LOGIC|LBL)\\b", "\\b(ACC|CNT|Skip|Offset|PSPD|RT_LD|AP_LD|Tool_Offset)" }, 2..) |p, i| {
        const m = try b.mode(&s, "keyword");
        try s.put(m, "begin", try s.text(p));
        try s.index(a, @intCast(i), m);
    }
    const num = try b.mode(&s, "number");
    try s.put(num, "begin", try s.text("\\d+(sec|msec|mm/sec|cm/min|inch/min|deg/sec|mm|in|cm)?\\b"));
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 5, num);
    for ([_][2][]const u8{ .{ "//", "[;$]" }, .{ "!", "[;$]" }, .{ "--eg:", "$" } }, 6..) |p, i| {
        const f = try s.get(h, "COMMENT");
        const begin = try s.text(p[0]);
        const end = try s.text(p[1]);
        try s.index(a, @intCast(i), try s.call(f, h, &.{ begin, end }));
    }
    try s.index(a, 9, try s.get(h, "QUOTE_STRING_MODE"));
    const str = try b.mode(&s, "string");
    try s.put(str, "begin", try s.text("'"));
    try s.put(str, "end", try s.text("'"));
    try s.index(a, 10, str);
    try s.index(a, 11, try s.get(h, "C_NUMBER_MODE"));
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try s.text("\\$[A-Za-z0-9_]+"));
    try s.index(a, 12, variable);
    try s.put(lang, "contains", a);
    return b.c.JS_DupValue(e.context, lang);
}
