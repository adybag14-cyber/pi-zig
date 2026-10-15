//! Actual highlight.js10.7.3 Mizar factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "mizar", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Mizar"));
    try s.put(language, "keywords", try s.text("environ vocabularies notations constructors definitions registrations theorems schemes requirements begin end definition registration cluster existence pred func defpred deffunc theorem proof let take assume then thus hence ex for st holds consider reconsider such that and in provided of as from be being by means equals implies iff redefine define now not or attr is mode suppose per cases set thesis contradiction scheme reserve struct correctness compatibility coherence symmetry assymetry reflexivity irreflexivity connectedness uniqueness commutativity idempotence involutiveness projectivity"));
    const comment_function = try s.get(hljs, "COMMENT");
    try s.put(language, "contains", try b.list(&s, &.{try s.call(comment_function, hljs, &.{ try s.text("::"), try s.text("$") })}));
    return b.c.JS_DupValue(engine.context, language);
}
