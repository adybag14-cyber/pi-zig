//! Actual highlight.js10.7.3 Gradle factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "gradle", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Gradle"));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("task project allprojects subprojects artifacts buildscript configurations dependencies repositories sourceSets description delete from into include exclude source classpath destinationDir includes options sourceCompatibility targetCompatibility group flatDir doLast doFirst flatten todir fromdir ant def abstract break case catch continue default do else extends final finally for if implements instanceof native new private protected public return static switch synchronized throw throws transient try volatile while strictfp package import false null super this true antlrtask checkstyle codenarc copy boolean byte char class double float int interface long short void compile runTime file fileTree abs any append asList asWritable call collect compareTo count div dump each eachByte eachFile eachLine every find findAll flatten getAt getErr getIn getOut getText grep immutable inject inspect intersect invokeMethods isCase join leftShift minus multiply newInputStream newOutputStream newPrintWriter newReader newWriter next plus pop power previous print println push putAt read readBytes readLines reverse reverseEach round size sort splitEachLine step subMap times toInteger toList tokenize upto waitForOrKill withPrintWriter withReader withStream withWriter withWriterAppend write writeLine"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE"), try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), try s.get(hljs, "NUMBER_MODE"), try s.get(hljs, "REGEXP_MODE") }));
    return b.c.JS_DupValue(e.context, language);
}
