//! Actual highlight.js 10.7.3 XL factory; source-only, unqualified.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "xl", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const kw = try s.object();
    try s.put(kw, "$pattern", try b.rx(&s, "[a-zA-Z][a-zA-Z0-9_?]*"));
    try s.put(kw, "keyword", try s.text("if then else do while until for loop import with is as where when by data constant integer real text name boolean symbol infix prefix postfix block tree"));
    try s.put(kw, "literal", try s.text("true false nil"));
    try s.put(kw, "built_in", try s.text("in mod rem and or xor not abs sign floor ceil sqrt sin cos tan asin acos atan exp expm1 log log2 log10 log1p pi at text_length text_range text_find text_replace contains page slide basic_slide title_slide title subtitle fade_in fade_out fade_at clear_color color line_color line_width texture_wrap texture_transform texture scale_?x scale_?y scale_?z? translate_?x translate_?y translate_?z? rotate_?x rotate_?y rotate_?z? rectangle circle ellipse sphere path line_to move_to quad_to curve_to theme background contents locally time mouse_?x mouse_?y mouse_buttons ObjectLoader Animate MovieCredits Slides Filters Shading Materials LensFlare Mapping VLCAudioVideo StereoDecoder PointCloud NetworkAccess RemoteControl RegExp ChromaKey Snowfall NodeJS Speech Charts"));
    const dq = try b.mode(&s, "string");
    try s.put(dq, "begin", try s.text("\""));
    try s.put(dq, "end", try s.text("\""));
    try s.put(dq, "illegal", try s.text("\\n"));
    const sq = try b.mode(&s, "string");
    try s.put(sq, "begin", try s.text("'"));
    try s.put(sq, "end", try s.text("'"));
    try s.put(sq, "illegal", try s.text("\\n"));
    const long = try b.mode(&s, "string");
    try s.put(long, "begin", try s.text("<<"));
    try s.put(long, "end", try s.text(">>"));
    const num = try b.mode(&s, "number");
    try s.put(num, "begin", try s.text("[0-9]+#[0-9A-Z_]+(\\.[0-9-A-Z_]+)?#?([Ee][+-]?[0-9]+)?"));
    const imp = try s.object();
    try s.put(imp, "beginKeywords", try s.text("import"));
    try s.put(imp, "end", try s.text("$"));
    try s.put(imp, "keywords", kw);
    try s.put(imp, "contains", try b.list(&s, &.{dq}));
    const fun = try b.mode(&s, "function");
    try s.put(fun, "begin", try b.rx(&s, "[a-z][^\\n]*->"));
    try s.put(fun, "returnBegin", b.boolean(&s, true));
    try s.put(fun, "end", try b.rx(&s, "->"));
    const inherit = try s.get(h, "inherit");
    const title = try s.get(h, "TITLE_MODE");
    const opt = try s.object();
    const starts = try s.object();
    try s.put(starts, "endsWithParent", b.boolean(&s, true));
    try s.put(starts, "keywords", kw);
    try s.put(opt, "starts", starts);
    try s.put(fun, "contains", try b.list(&s, &.{try s.call(inherit, h, &.{ title, opt })}));
    const l = try s.object();
    try s.put(l, "name", try s.text("XL"));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("tao")}));
    try s.put(l, "keywords", kw);
    try s.put(l, "contains", try b.list(&s, &.{ try s.get(h, "C_LINE_COMMENT_MODE"), try s.get(h, "C_BLOCK_COMMENT_MODE"), dq, sq, long, fun, imp, num, try s.get(h, "NUMBER_MODE") }));
    return b.c.JS_DupValue(e.context, l);
}
