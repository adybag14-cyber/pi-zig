//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "purebasic", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const str = try b.mode(&s, "string");
    try s.put(str, "begin", try s.text("(~)?\""));
    try s.put(str, "end", try s.text("\""));
    try s.put(str, "illegal", try s.text("\\n"));
    const constant = try b.mode(&s, "symbol");
    try s.put(constant, "begin", try s.text("#[a-zA-Z_]\\w*\\$?"));
    const l = try s.object();
    try s.put(l, "name", try s.text("PureBASIC"));
    try s.put(l, "aliases", try b.list(&s, &.{ try s.text("pb"), try s.text("pbi") }));
    try s.put(l, "keywords", try s.text(source_text));
    const f = try s.get(h, "COMMENT");
    const cb = try s.text(";");
    const ce = try s.text("$");
    const opt = try s.object();
    try s.put(opt, "relevance", b.c.JS_NewInt32(e.context, 0));
    const a = try b.list(&s, &.{try s.call(f, h, &.{ cb, ce, opt })});
    const fun = try b.mode(&s, "function");
    try s.put(fun, "begin", try s.text("\\b(Procedure|Declare)(C|CDLL|DLL)?\\b"));
    try s.put(fun, "end", try s.text("\\("));
    try s.put(fun, "excludeEnd", b.boolean(&s, true));
    try s.put(fun, "returnBegin", b.boolean(&s, true));
    const keyword = try b.mode(&s, "keyword");
    try s.put(keyword, "begin", try s.text("(Procedure|Declare)(C|CDLL|DLL)?"));
    try s.put(keyword, "excludeEnd", b.boolean(&s, true));
    const type_mode = try b.mode(&s, "type");
    try s.put(type_mode, "begin", try s.text("\\.\\w*"));
    try s.put(fun, "contains", try b.list(&s, &.{ keyword, type_mode, try s.get(h, "UNDERSCORE_TITLE_MODE") }));
    try s.index(a, 1, fun);
    try s.index(a, 2, str);
    try s.index(a, 3, constant);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_text = "Align And Array As Break CallDebugger Case CompilerCase CompilerDefault CompilerElse CompilerElseIf CompilerEndIf CompilerEndSelect CompilerError CompilerIf CompilerSelect CompilerWarning Continue Data DataSection Debug DebugLevel Declare DeclareC DeclareCDLL DeclareDLL DeclareModule Default Define Dim DisableASM DisableDebugger DisableExplicit Else ElseIf EnableASM EnableDebugger EnableExplicit End EndDataSection EndDeclareModule EndEnumeration EndIf EndImport EndInterface EndMacro EndModule EndProcedure EndSelect EndStructure EndStructureUnion EndWith Enumeration EnumerationBinary Extends FakeReturn For ForEach ForEver Global Gosub Goto If Import ImportC IncludeBinary IncludeFile IncludePath Interface List Macro MacroExpandedCount Map Module NewList NewMap Next Not Or Procedure ProcedureC ProcedureCDLL ProcedureDLL ProcedureReturn Protected Prototype PrototypeC ReDim Read Repeat Restore Return Runtime Select Shared Static Step Structure StructureUnion Swap Threaded To UndefineMacro Until Until  UnuseModule UseModule Wend While With XIncludeFile XOr";
