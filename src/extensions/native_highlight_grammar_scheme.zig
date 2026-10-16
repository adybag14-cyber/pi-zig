//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "scheme", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const ident_pattern = source_SCHEME_IDENT_RE;
    const simple = "(-|\\+)?\\d+([./]\\d+)?";
    const kw = try s.object();
    try s.put(kw, "$pattern", try s.text(ident_pattern));
    try s.put(kw, "builtin-name", try s.text(source_builtin_name));
    const literal = try b.mode(&s, "literal");
    try s.put(literal, "begin", try s.text("(#t|#f|#\\\\" ++ ident_pattern ++ "|#\\\\.)"));
    const num = try b.mode(&s, "number");
    const nv = try s.array();
    for ([_][]const u8{ simple, simple ++ "[+\\-]" ++ simple ++ "i", "#b[0-1]+(/[0-1]+)?", "#o[0-7]+(/[0-7]+)?", "#x[0-9a-f]+(/[0-9a-f]+)?" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        if (i < 2) try s.put(m, "relevance", b.c.JS_NewInt32(e.context, 0));
        try s.index(nv, @intCast(i), m);
    }
    try s.put(num, "variants", nv);
    const str = try s.get(h, "QUOTE_STRING_MODE");
    const cf1 = try s.get(h, "COMMENT");
    const cb1 = try s.text(";");
    const ce1 = try s.text("$");
    const co1 = try s.object();
    try s.put(co1, "relevance", b.c.JS_NewInt32(e.context, 0));
    const comments = try b.list(&s, &.{try s.call(cf1, h, &.{ cb1, ce1, co1 })});
    const cf2 = try s.get(h, "COMMENT");
    const cb2 = try s.text("#\\|");
    const ce2 = try s.text("\\|#");
    try s.index(comments, 1, try s.call(cf2, h, &.{ cb2, ce2 }));
    const ident = try s.object();
    try s.put(ident, "begin", try s.text(ident_pattern));
    try s.put(ident, "relevance", b.c.JS_NewInt32(e.context, 0));
    const quoted_ident = try b.mode(&s, "symbol");
    try s.put(quoted_ident, "begin", try s.text("'" ++ ident_pattern));
    const body = try s.object();
    try s.put(body, "endsWithParent", b.boolean(&s, true));
    try s.put(body, "relevance", b.c.JS_NewInt32(e.context, 0));
    const quoted = try s.object();
    const qv1 = try s.object();
    try s.put(qv1, "begin", try b.rx(&s, "'"));
    const qv2 = try s.object();
    try s.put(qv2, "begin", try s.text("`"));
    try s.put(quoted, "variants", try b.list(&s, &.{ qv1, qv2 }));
    const qp = try s.object();
    try s.put(qp, "begin", try s.text("\\("));
    try s.put(qp, "end", try s.text("\\)"));
    try s.put(qp, "contains", try b.list(&s, &.{ try s.text("self"), literal, str, num, ident, quoted_ident }));
    try s.put(quoted, "contains", try b.list(&s, &.{qp}));
    const name = try b.mode(&s, "name");
    try s.put(name, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(name, "begin", try s.text(ident_pattern));
    try s.put(name, "keywords", kw);
    const lambda = try s.object();
    try s.put(lambda, "begin", try b.rx(&s, "lambda"));
    try s.put(lambda, "endsWithParent", b.boolean(&s, true));
    try s.put(lambda, "returnBegin", b.boolean(&s, true));
    const params = try s.object();
    try s.put(params, "endsParent", b.boolean(&s, true));
    const pv = try s.array();
    for ([_][2][]const u8{ .{ "\\(", "\\)" }, .{ "\\[", "\\]" } }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try b.rx(&s, p[0]));
        try s.put(m, "end", try b.rx(&s, p[1]));
        try s.index(pv, @intCast(i), m);
    }
    try s.put(params, "variants", pv);
    try s.put(params, "contains", try b.list(&s, &.{ident}));
    try s.put(lambda, "contains", try b.list(&s, &.{ name, params }));
    const list = try s.object();
    const lv = try s.array();
    for ([_][2][]const u8{ .{ "\\(", "\\)" }, .{ "\\[", "\\]" } }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p[0]));
        try s.put(m, "end", try s.text(p[1]));
        try s.index(lv, @intCast(i), m);
    }
    try s.put(list, "variants", lv);
    try s.put(list, "contains", try b.list(&s, &.{ lambda, name, body }));
    try s.set(body, "contains", try s.invoke(try b.list(&s, &.{ literal, num, str, ident, quoted_ident, quoted, list }), "concat", &.{comments}));
    const l = try s.object();
    try s.put(l, "name", try s.text("Scheme"));
    try s.put(l, "illegal", try b.rx(&s, "\\S"));
    const shebang = try s.get(h, "SHEBANG");
    try s.put(l, "contains", try s.invoke(try b.list(&s, &.{ try s.call(shebang, h, &.{}), num, str, quoted_ident, quoted, list }), "concat", &.{comments}));
    return b.c.JS_DupValue(e.context, l);
}
const source_builtin_name = "case-lambda call/cc class define-class exit-handler field import inherit init-field interface let*-values let-values let/ec mixin opt-lambda override protect provide public rename require require-for-syntax syntax syntax-case syntax-error unit/sig unless when with-syntax and begin call-with-current-continuation call-with-input-file call-with-output-file case cond define define-syntax delay do dynamic-wind else for-each if lambda let let* let-syntax letrec letrec-syntax map or syntax-rules ' * + , ,@ - ... / ; < <= = => > >= ` abs acos angle append apply asin assoc assq assv atan boolean? caar cadr call-with-input-file call-with-output-file call-with-values car cdddar cddddr cdr ceiling char->integer char-alphabetic? char-ci<=? char-ci<? char-ci=? char-ci>=? char-ci>? char-downcase char-lower-case? char-numeric? char-ready? char-upcase char-upper-case? char-whitespace? char<=? char<? char=? char>=? char>? char? close-input-port close-output-port complex? cons cos current-input-port current-output-port denominator display eof-object? eq? equal? eqv? eval even? exact->inexact exact? exp expt floor force gcd imag-part inexact->exact inexact? input-port? integer->char integer? interaction-environment lcm length list list->string list->vector list-ref list-tail list? load log magnitude make-polar make-rectangular make-string make-vector max member memq memv min modulo negative? newline not null-environment null? number->string number? numerator odd? open-input-file open-output-file output-port? pair? peek-char port? positive? procedure? quasiquote quote quotient rational? rationalize read read-char real-part real? remainder reverse round scheme-report-environment set! set-car! set-cdr! sin sqrt string string->list string->number string->symbol string-append string-ci<=? string-ci<? string-ci=? string-ci>=? string-ci>? string-copy string-fill! string-length string-ref string-set! string<=? string<? string=? string>=? string>? string? substring symbol->string symbol? tan transcript-off transcript-on truncate values vector vector->list vector-fill! vector-length vector-ref vector-set! with-input-from-file with-output-to-file write write-char zero?";
const source_SCHEME_IDENT_RE = "[^\\(\\)\\[\\]\\{\\}\",'`;#|\\\\\\s]+";
