//! Actual highlight.js10.7.3 OpenSCAD factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "openscad", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const special = try b.mode(&s, "keyword");
    try s.put(special, "begin", try s.text("\\$(f[asn]|t|vp[rtd]|children)"));
    const literals = try b.mode(&s, "literal");
    try s.put(literals, "begin", try s.text("false|true|PI|undef"));
    const numbers = try b.mode(&s, "number");
    try s.put(numbers, "begin", try s.text("\\b\\d+(\\.\\d+)?(e-?\\d+)?"));
    try s.put(numbers, "relevance", b.c.JS_NewInt32(e.context, 0));
    const inherit = try s.get(hljs, "inherit");
    const quoted = try s.get(hljs, "QUOTE_STRING_MODE");
    const changes = try s.object();
    try s.put(changes, "illegal", b.c.pi_js_null());
    const string = try s.call(inherit, hljs, &.{ quoted, changes });
    const prepro = try b.mode(&s, "meta");
    const meta_keywords = try s.object();
    try s.put(meta_keywords, "meta-keyword", try s.text("include use"));
    try s.put(prepro, "keywords", meta_keywords);
    try s.put(prepro, "begin", try s.text("include|use <"));
    try s.put(prepro, "end", try s.text(">"));
    const params = try b.mode(&s, "params");
    try s.put(params, "begin", try s.text("\\("));
    try s.put(params, "end", try s.text("\\)"));
    try s.put(params, "contains", try b.list(&s, &.{ try s.text("self"), numbers, string, special, literals }));
    const modifiers = try s.object();
    try s.put(modifiers, "begin", try s.text("[*!#%]"));
    try s.put(modifiers, "relevance", b.c.JS_NewInt32(e.context, 0));
    const functions = try b.mode(&s, "function");
    try s.put(functions, "beginKeywords", try s.text("module function"));
    try s.put(functions, "end", try b.rx(&s, "=|\\{"));
    try s.put(functions, "contains", try b.list(&s, &.{ params, try s.get(hljs, "UNDERSCORE_TITLE_MODE") }));
    const language = try s.object();
    try s.put(language, "name", try s.text("OpenSCAD"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("scad")}));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("function module include use for intersection_for if else \\%"));
    try s.put(keywords, "literal", try s.text("false true PI undef"));
    try s.put(keywords, "built_in", try s.text("circle square polygon text sphere cube cylinder polyhedron translate rotate scale resize mirror multmatrix color offset hull minkowski union difference intersection abs sign sin cos tan acos asin atan atan2 floor round ceil ln log pow sqrt exp rands min max concat lookup str chr search version version_num norm cross parent_module echo import import_dxf dxf_linear_extrude linear_extrude rotate_extrude surface projection render children dxf_cross dxf_dim let assign"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE"), numbers, prepro, string, special, modifiers, functions }));
    return b.c.JS_DupValue(e.context, language);
}
