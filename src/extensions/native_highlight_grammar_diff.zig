//! Actual highlight.js10.7.3 Diff factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "diff", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Diff"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("patch")}));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "relevance", b.c.JS_NewInt32(e.context, 10));
    const variants = try s.array();
    inline for (.{ "^@@ +-\\d+,\\d+ +\\+\\d+,\\d+ +@@", "^\\*\\*\\* +\\d+,\\d+ +\\*\\*\\*\\*$", "^--- +\\d+,\\d+ +----$" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try b.rx(&s, pattern));
        try s.index(variants, index, variant);
    }
    try s.put(meta, "variants", variants);
    const comment = try b.mode(&s, "comment");
    const comments = try s.array();
    inline for (.{ "Index: ", "^index", "={3,}", "^-{3}", "^\\*{3} ", "^\\+{3}", "^\\*{15}$", "^diff --git" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try b.rx(&s, pattern));
        if (index != 6) try s.put(variant, "end", try b.rx(&s, "$"));
        try s.index(comments, index, variant);
    }
    try s.put(comment, "variants", comments);
    const contains = try b.list(&s, &.{ meta, comment });
    inline for (.{ .{ "addition", "^\\+" }, .{ "deletion", "^-" }, .{ "addition", "^!" } }, 0..) |entry, index| {
        const mode = try b.mode(&s, entry[0]);
        try s.put(mode, "begin", try b.rx(&s, entry[1]));
        try s.put(mode, "end", try b.rx(&s, "$"));
        try s.index(contains, @intCast(index + 2), mode);
    }
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
