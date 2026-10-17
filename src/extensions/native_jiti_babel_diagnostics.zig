//! Genuine native parser diagnostics. Positions come from the actual syntax
//! tree, never a fixture lookup or invented Babel/V8 parser result.
const std=@import("std");
const v=@import("native_ai_provider_values.zig");
const c=@cImport({@cInclude("tree_sitter/api.h");});
extern fn tree_sitter_typescript() ?*const c.TSLanguage;
fn firstFailure(node:c.TSNode,depth:usize)!?c.TSNode{
    if(depth>256)return error.TypeScriptNestingLimit;
    // Prefer the actual deepest leftmost failure, including missing tokens.
    for(0..c.ts_node_child_count(node))|i|{const child=c.ts_node_child(node,@intCast(i));if(c.ts_node_has_error(child) or c.ts_node_is_missing(child))if(try firstFailure(child,depth+1))|failure|return failure;}
    return if(c.ts_node_is_error(node) or c.ts_node_is_missing(node))node else null;
}
fn units(bytes:[]const u8)usize{var count:usize=0;for(bytes)|byte|{if((byte&0xC0)==0x80)continue;count+=if(byte>=0xF0)@as(usize,2) else 1;}return count;}
pub fn result(engine:*v.em.Engine,source:[]const u8,filename:v.c.JSValue)!v.c.JSValue{
    engine.native_exception_diagnostics_suppressed+=1;defer engine.native_exception_diagnostics_suppressed-=1;
    const parser=c.ts_parser_new() orelse return error.OutOfMemory;defer c.ts_parser_delete(parser);
    if(!c.ts_parser_set_language(parser,tree_sitter_typescript()))return error.TypeScriptParserAbiMismatch;
    const tree=c.ts_parser_parse_string(parser,null,source.ptr,@intCast(source.len)) orelse return error.OutOfMemory;defer c.ts_tree_delete(tree);
    const failure=(try firstFailure(c.ts_tree_root_node(tree),0)) orelse return error.RequiredActualParserFailure;
    const point=c.ts_node_start_point(failure);const offset=c.ts_node_start_byte(failure);
    const line_start=offset-point.column;
    const index=units(source[0..offset]);const column=units(source[line_start..offset]);
    const message=try std.fmt.allocPrint(engine.gpa,"Native TypeScript syntax error at line {d}, column {d}",.{point.row+1,column});defer engine.gpa.free(message);
    const terminated=try engine.gpa.dupeZ(u8,message);defer engine.gpa.free(terminated);
    const generation=engine.native_allocation_generation;
    _=engine.checked(v.c.JS_ThrowSyntaxError(engine.context,"%s",terminated.ptr)) catch |err| {
        if(err!=error.JavaScriptException)return err;
    };
    const reason=engine.captured_exception orelse return error.MissingNativeParserSyntaxReason;
    if(v.c.JS_IsUncatchableError(reason))return error.JavaScriptException;
    try @import("native_async_body.zig").rethrowRecognizedAllocation(engine,reason,generation);
    engine.captured_exception=null;
    var s:v.Scope=.{.engine=engine};defer s.deinit();_ = try s.own(reason);
    const loc=try s.object();try s.put(loc,"line",v.c.JS_NewInt64(engine.context,point.row+1));try s.put(loc,"column",v.c.JS_NewInt64(engine.context,@intCast(column)));try s.put(loc,"index",v.c.JS_NewInt64(engine.context,@intCast(index)));
    try s.put(reason,"loc",loc);try s.put(reason,"code",try s.text("PI_JITI_NATIVE_PARSE_ERROR"));
    const info=try s.object();try s.put(info,"filename",filename);try s.put(info,"line",try s.get(loc,"line"));try s.put(info,"column",try s.get(loc,"column"));try s.put(info,"code",try s.text("NativeSyntaxError"));try s.put(info,"message",try s.text(message));
    const serialized=try s.invoke(try s.global("JSON"),"stringify",&.{info});
    const code=try s.concat(try s.text("exports.__JITI_ERROR__ = "),serialized);
    const output=try s.object();try s.put(output,"error",reason);try s.put(output,"code",code);
    return v.c.JS_DupValue(engine.context,output);
}
