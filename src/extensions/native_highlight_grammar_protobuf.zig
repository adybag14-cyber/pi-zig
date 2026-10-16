//! Actual highlight.js 10.7.3 Protocol Buffers factory; source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;

fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "protobuf", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Protocol Buffers"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("package import option optional required repeated group oneof"));
    try s.put(keywords, "built_in", try s.text("double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes"));
    try s.put(keywords, "literal", try s.text("true false"));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.index(contains, 1, try s.get(hljs, "NUMBER_MODE"));
    try s.index(contains, 2, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(contains, 3, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    const class_mode = try s.object();
    try s.put(class_mode, "className", try s.text("class"));
    try s.put(class_mode, "beginKeywords", try s.text("message enum service"));
    try s.put(class_mode, "end", try literal(&s, "\\{"));
    try s.put(class_mode, "illegal", try literal(&s, "\\n"));
    // Preserve the live inherit getter before TITLE_MODE and the changes object.
    const inherit = try s.get(hljs, "inherit");
    const title = try s.get(hljs, "TITLE_MODE");
    const changes = try s.object();
    const starts = try s.object();
    try s.put(starts, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.put(starts, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(changes, "starts", starts);
    try s.put(class_mode, "contains", try list(&s, &.{try s.call(inherit, hljs, &.{ title, changes })}));
    try s.index(contains, 4, class_mode);
    const function = try s.object();
    try s.put(function, "className", try s.text("function"));
    try s.put(function, "beginKeywords", try s.text("rpc"));
    try s.put(function, "end", try literal(&s, "[{;]"));
    try s.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(function, "keywords", try s.text("rpc returns"));
    try s.index(contains, 5, function);
    const enum_item = try s.object();
    try s.put(enum_item, "begin", try literal(&s, "^\\s*[A-Z_]+(?=\\s*=[^\\n]+;$)"));
    try s.index(contains, 6, enum_item);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
