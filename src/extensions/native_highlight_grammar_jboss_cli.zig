//! Actual highlight.js10.7.3 JBoss CLI factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "jbossCli", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const param = try s.object();
    try s.put(param, "begin", try b.rx(&s, "[\\w-]+ *="));
    try s.put(param, "returnBegin", b.boolean(&s, true));
    try s.put(param, "relevance", b.c.JS_NewInt32(e.context, 0));
    const attr = try b.mode(&s, "attr");
    try s.put(attr, "begin", try b.rx(&s, "[\\w-]+"));
    try s.put(param, "contains", try b.list(&s, &.{attr}));
    const block = try b.mode(&s, "params");
    try s.put(block, "begin", try b.rx(&s, "\\("));
    try s.put(block, "end", try b.rx(&s, "\\)"));
    try s.put(block, "contains", try b.list(&s, &.{param}));
    try s.put(block, "relevance", b.c.JS_NewInt32(e.context, 0));
    const operation = try b.mode(&s, "function");
    try s.put(operation, "begin", try b.rx(&s, ":[\\w\\-.]+"));
    try s.put(operation, "relevance", b.c.JS_NewInt32(e.context, 0));
    const path = try b.mode(&s, "string");
    try s.put(path, "begin", try b.rx(&s, "\\B([\\/.])[\\w\\-.\\/=]+"));
    const command = try b.mode(&s, "params");
    try s.put(command, "begin", try b.rx(&s, "--[\\w\\-=\\/]+"));
    const language = try s.object();
    try s.put(language, "name", try s.text("JBoss CLI"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("wildfly-cli")}));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try s.text("[a-z-]+"));
    try s.put(keywords, "keyword", try s.text("alias batch cd clear command connect connection-factory connection-info data-source deploy deployment-info deployment-overlay echo echo-dmr help history if jdbc-driver-info jms-queue|20 jms-topic|20 ls patch pwd quit read-attribute read-operation reload rollout-plan run-batch set shutdown try unalias undeploy unset version xa-data-source"));
    try s.put(keywords, "literal", try s.text("true false"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ try s.get(hljs, "HASH_COMMENT_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), command, operation, path, block }));
    return b.c.JS_DupValue(e.context, language);
}
