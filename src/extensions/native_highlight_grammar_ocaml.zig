//! Actual highlight.js10.7.3 OCaml factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "ocaml", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    return @import("native_highlight_grammar_ml_family.zig").build(e, hljs, true);
}
