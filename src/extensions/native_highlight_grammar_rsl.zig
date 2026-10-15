//! Actual highlight.js10.7.3 RenderMan RSL factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "rsl", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("RenderMan RSL"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("float color point normal vector matrix while for if do return else break extern continue"));
    try s.put(keywords, "built_in", try s.text("abs acos ambient area asin atan atmosphere attribute calculatenormal ceil cellnoise clamp comp concat cos degrees depth Deriv diffuse distance Du Dv environment exp faceforward filterstep floor format fresnel incident length lightsource log match max min mod noise normalize ntransform opposite option phong pnoise pow printf ptlined radians random reflect refract renderinfo round setcomp setxcomp setycomp setzcomp shadow sign sin smoothstep specular specularbrdf spline sqrt step tan texture textureinfo trace transform vtransform xcomp ycomp zcomp"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "illegal", try s.text("</"));
    const contains = try b.list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "C_NUMBER_MODE") });
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("#"));
    try s.put(meta, "end", try s.text("$"));
    try s.index(contains, 5, meta);
    const class = try b.mode(&s, "class");
    try s.put(class, "beginKeywords", try s.text("surface displacement light volume imager"));
    try s.put(class, "end", try s.text("\\("));
    try s.index(contains, 6, class);
    const special = try s.object();
    try s.put(special, "beginKeywords", try s.text("illuminate illuminance gather"));
    try s.put(special, "end", try s.text("\\("));
    try s.index(contains, 7, special);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
