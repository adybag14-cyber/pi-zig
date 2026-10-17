//! Native syntax-tree token generation and the actual empty-source-name inline
//! map profile. Full Babel byte formatting is an independently reported axis.
const std=@import("std");
const v=@import("native_ai_provider_values.zig");
const c=@cImport({@cInclude("tree_sitter/api.h");});
extern fn tree_sitter_typescript() ?*const c.TSLanguage;
const Token=struct{start:usize,end:usize,comment:bool=false};
fn kind(node:c.TSNode)[]const u8{return std.mem.span(c.ts_node_type(node));}
fn collect(gpa:std.mem.Allocator,node:c.TSNode,tokens:*std.ArrayList(Token),depth:usize)!void{
    if(depth>256)return error.TypeScriptNestingLimit;
    const name=kind(node);const count=c.ts_node_child_count(node);
    if(count==0 or std.mem.eql(u8,name,"string") or std.mem.eql(u8,name,"regex") or std.mem.eql(u8,name,"template_string") or std.mem.eql(u8,name,"comment")){
        const a=c.ts_node_start_byte(node);const b=c.ts_node_end_byte(node);if(a!=b)try tokens.append(gpa,.{.start=a,.end=b,.comment=std.mem.eql(u8,name,"comment")});return;
    }
    for(0..count)|i|try collect(gpa,c.ts_node_child(node,@intCast(i)),tokens,depth+1);
}
fn same(a:[]const u8,b:[]const u8)bool{return std.mem.eql(u8,a,b);}
fn word(byte:u8)bool{return std.ascii.isAlphanumeric(byte) or byte=='_' or byte=='$' or byte>=0x80;}
fn operator(value:[]const u8)bool{inline for(.{"=","+","-","*","/","%","**","==","===","!=","!==","<",">","<=",">=","&&","||","??","+=","-=","*=","/=","%=","&&=","||=","??=","=>","&","|","^","<<",">>",">>>"})|item|if(same(value,item))return true;return false;}
fn lineTerminator(gap:[]const u8)bool{
    return std.mem.indexOfAny(u8,gap,"\r\n")!=null or
        std.mem.indexOf(u8,gap,"\xE2\x80\xA8")!=null or std.mem.indexOf(u8,gap,"\xE2\x80\xA9")!=null;
}
const Printer=struct{
    output:std.Io.Writer.Allocating,indent:usize=0,line_start:bool=true,last:u8=0,
    fn text(self:*Printer,value:[]const u8)!void{if(self.line_start){for(0..self.indent)|_|try self.output.writer.writeAll("  ");self.line_start=false;}try self.output.writer.writeAll(value);if(value.len!=0)self.last=value[value.len-1];}
    fn space(self:*Printer)!void{if(!self.line_start and self.last!=' '){try self.output.writer.writeByte(' ');self.last=' ';}}
    fn newline(self:*Printer)!void{if(!self.line_start){try self.output.writer.writeByte('\n');self.line_start=true;self.last='\n';}}
};
pub fn pretty(gpa:std.mem.Allocator,input:[]const u8)![]u8{
    return prettyBody(gpa,input) catch|err|return if(err==error.WriteFailed)error.OutOfMemory else err;
}
fn prettyBody(gpa:std.mem.Allocator,input:[]const u8)![]u8{
    const parser=c.ts_parser_new() orelse return error.OutOfMemory;defer c.ts_parser_delete(parser);
    if(!c.ts_parser_set_language(parser,tree_sitter_typescript()))return error.TypeScriptParserAbiMismatch;
    const tree=c.ts_parser_parse_string(parser,null,input.ptr,@intCast(input.len)) orelse return error.OutOfMemory;defer c.ts_tree_delete(tree);
    const root=c.ts_tree_root_node(tree);if(c.ts_node_has_error(root))return error.NativeBabelGeneratedSyntaxInvalid;
    var tokens:std.ArrayList(Token)=.empty;defer tokens.deinit(gpa);try collect(gpa,root,&tokens,0);
    var p:Printer=.{.output=.init(gpa)};defer p.output.deinit();var parens:usize=0;var previous:[]const u8="";var previous_end:usize=0;
    for(tokens.items,0..)|token,index|{
        const value=input[token.start..token.end];const next=if(index+1<tokens.items.len)input[tokens.items[index+1].start..tokens.items[index+1].end] else "";
        // Original line terminators carry ASI/return/async meaning. Never erase
        // one merely to fit a formatting style; string/template/regex are atomic.
        const gap=input[previous_end..token.start];
        if(lineTerminator(gap))try p.newline() else if(gap.len!=0)try p.space();
        // Keep every existing horizontal boundary, including number/member and
        // regex/word boundaries not covered by identifier/operator heuristics.
        if(same(value,"}")){p.indent-|=1;if(!same(previous,"{"))try p.newline();}
        const join_word=previous.len!=0 and value.len!=0 and word(previous[previous.len-1]) and word(value[0]);
        if(join_word or operator(value) or operator(previous) or same(value,"{") or same(previous,",") or same(previous,":"))try p.space();
        if(same(value,"(") and (same(previous,"if") or same(previous,"for") or same(previous,"while") or same(previous,"switch") or same(previous,"catch") or same(previous,"with")))try p.space();
        try p.text(value);
        if(same(value,"("))parens+=1 else if(same(value,")"))parens-|=1;
        if(same(value,"{")){p.indent+=1;if(!same(next,"}"))try p.newline();}
        if(same(value,";")){if(parens==0)try p.newline() else try p.space();}
        if(same(value,"}")){
            if(same(next,"else") or same(next,"catch") or same(next,"finally") or same(next,"while"))try p.space()
            else if(next.len!=0 and !same(next,")") and !same(next,"]") and !same(next,";") and !same(next,",") and !same(next,".") and !same(next,"?."))try p.newline();
        }
        if(token.comment and std.mem.startsWith(u8,value,"//"))try p.newline();
        previous=value;previous_end=token.end;
    }
    return p.output.toOwnedSlice();
}
/// jiti's fixed Babel _opts.filename is empty and alternate filename/sourceRoot/
/// inputMap options are not admitted. Primary Babel source-map.ts and pinned
/// gen-mapping0.3.13 skip mappings with that empty source. setSourceContent still
/// retains the actual source under ""; no guessed source-position map is made.
pub fn inlineMap(engine:*v.em.Engine,code:v.c.JSValue,source:v.c.JSValue)!v.c.JSValue{
    var s:v.Scope=.{.engine=engine};defer s.deinit();
    const map=try s.object();try s.put(map,"version",v.c.JS_NewInt32(engine.context,3));try s.put(map,"names",try s.array());
    const sources=try s.array();try s.index(sources,0,try s.text(""));try s.put(map,"sources",sources);
    const contents=try s.array();try s.index(contents,0,source);try s.put(map,"sourcesContent",contents);
    try s.put(map,"mappings",try s.text(""));try s.put(map,"ignoreList",try s.array());
    const text=try s.invoke(try s.global("JSON"),"stringify",&.{map});const bytes=try engine.toString(text);defer engine.gpa.free(bytes);
    const encoded=try engine.gpa.alloc(u8,std.base64.standard.Encoder.calcSize(bytes.len));defer engine.gpa.free(encoded);
    _=std.base64.standard.Encoder.encode(encoded,bytes);
    const marker=try s.concat(try s.text("\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,"),try s.text(encoded));
    return v.c.JS_DupValue(engine.context,try s.concat(code,marker));
}
