//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "mercury", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const kw = try s.object();
    try s.put(kw, "keyword", try s.text(source_keyword));
    try s.put(kw, "meta", try s.text(source_meta));
    try s.put(kw, "built_in", try s.text(source_built_in));
    const f = try s.get(h, "COMMENT");
    const cb = try s.text("%");
    const ce = try s.text("$");
    const comment = try s.call(f, h, &.{ cb, ce });
    const num = try b.mode(&s, "number");
    try s.put(num, "begin", try s.text("0'.\\|0[box][0-9a-fA-F]*"));
    const ia = try s.get(h, "inherit");
    const apos = try s.get(h, "APOS_STRING_MODE");
    const ao = try s.object();
    try s.put(ao, "relevance", b.c.JS_NewInt32(e.context, 0));
    const atom = try s.call(ia, h, &.{ apos, ao });
    const iq = try s.get(h, "inherit");
    const quote = try s.get(h, "QUOTE_STRING_MODE");
    const qo = try s.object();
    try s.put(qo, "relevance", b.c.JS_NewInt32(e.context, 0));
    const str = try s.call(iq, h, &.{ quote, qo });
    const fmt = try b.mode(&s, "subst");
    try s.put(fmt, "begin", try s.text("\\\\[abfnrtv]\\|\\\\x[0-9a-fA-F]*\\\\\\|%[-+# *.0-9]*[dioxXucsfeEgGp]"));
    try s.put(fmt, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.set(str, "contains", try s.invoke(try s.get(str, "contains"), "slice", &.{}));
    _ = try s.invoke(try s.get(str, "contains"), "push", &.{fmt});
    const implication = try b.mode(&s, "built_in");
    const iv = try s.array();
    for ([_][]const u8{ "<=>", "<=", "=>", "/\\\\", "\\\\/" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        if (i == 1 or i == 2) try s.put(m, "relevance", b.c.JS_NewInt32(e.context, 0));
        try s.index(iv, @intCast(i), m);
    }
    try s.put(implication, "variants", iv);
    const conjunction = try b.mode(&s, "built_in");
    const c1 = try s.object();
    try s.put(c1, "begin", try s.text(":-\\|-->"));
    const c2 = try s.object();
    try s.put(c2, "begin", try s.text("="));
    try s.put(c2, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(conjunction, "variants", try b.list(&s, &.{ c1, c2 }));
    const l = try s.object();
    try s.put(l, "name", try s.text("Mercury"));
    try s.put(l, "aliases", try b.list(&s, &.{ try s.text("m"), try s.text("moo") }));
    try s.put(l, "keywords", kw);
    const a = try b.list(&s, &.{ implication, conjunction, comment, try s.get(h, "C_BLOCK_COMMENT_MODE"), num, try s.get(h, "NUMBER_MODE"), atom, str });
    const booster1 = try s.object();
    try s.put(booster1, "begin", try b.rx(&s, ":-"));
    try s.index(a, 8, booster1);
    const booster2 = try s.object();
    try s.put(booster2, "begin", try b.rx(&s, "\\.$"));
    try s.index(a, 9, booster2);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_keyword = "module use_module import_module include_module end_module initialise mutable initialize finalize finalise interface implementation pred mode func type inst solver any_pred any_func is semidet det nondet multi erroneous failure cc_nondet cc_multi typeclass instance where pragma promise external trace atomic or_else require_complete_switch require_det require_semidet require_multi require_nondet require_cc_multi require_cc_nondet require_erroneous require_failure";
const source_meta = "inline no_inline type_spec source_file fact_table obsolete memo loop_check minimal_model terminates does_not_terminate check_termination promise_equivalent_clauses foreign_proc foreign_decl foreign_code foreign_type foreign_import_module foreign_export_enum foreign_export foreign_enum may_call_mercury will_not_call_mercury thread_safe not_thread_safe maybe_thread_safe promise_pure promise_semipure tabled_for_io local untrailed trailed attach_to_io_state can_pass_as_mercury_type stable will_not_throw_exception may_modify_trail will_not_modify_trail may_duplicate may_not_duplicate affects_liveness does_not_affect_liveness doesnt_affect_liveness no_sharing unknown_sharing sharing";
const source_built_in = "some all not if then else true fail false try catch catch_any semidet_true semidet_false semidet_fail impure_true impure semipure";
