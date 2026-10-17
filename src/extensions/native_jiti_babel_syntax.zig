//! Native AST passes for actual legacy class decorators and top-level explicit
//! resource declarations. Algorithm authority and Babel MIT license are retained
//! in the prospective source packet. No fixture ID or expected output is read.
const std=@import("std");
const c=@cImport({@cInclude("tree_sitter/api.h");});
extern fn tree_sitter_typescript() ?*const c.TSLanguage;
pub const Resource=struct{context:[]u8,helper:[]u8,asynchronous:bool};
pub const Prepared=struct{
    source:[]u8,resource:?Resource=null,
    pub fn deinit(self:Prepared,gpa:std.mem.Allocator)void{
        gpa.free(self.source);if(self.resource)|item|{gpa.free(item.context);gpa.free(item.helper);}
    }
};
const Edit=struct{start:usize,end:usize,replacement:[]u8};
fn kind(node:c.TSNode)[]const u8{return if(c.ts_node_is_null(node))"" else std.mem.span(c.ts_node_type(node));}
fn is(node:c.TSNode,name:[]const u8)bool{return std.mem.eql(u8,kind(node),name);}
fn field(node:c.TSNode,comptime name:[:0]const u8)c.TSNode{return c.ts_node_child_by_field_name(node,name,name.len);}
fn start(node:c.TSNode)usize{return c.ts_node_start_byte(node);}
fn end(node:c.TSNode)usize{return c.ts_node_end_byte(node);}
fn token(node:c.TSNode,name:[]const u8)?c.TSNode{for(0..c.ts_node_child_count(node))|i|{const child=c.ts_node_child(node,@intCast(i));if(is(child,name))return child;}return null;}
const Tree=struct{
    parser:*c.TSParser,tree:*c.TSTree,
    fn init(input:[]const u8)!Tree{
        if(input.len>16*1024*1024)return error.ExtensionSourceTooLarge;
        const parser=c.ts_parser_new() orelse return error.OutOfMemory;errdefer c.ts_parser_delete(parser);
        if(!c.ts_parser_set_language(parser,tree_sitter_typescript()))return error.TypeScriptParserAbiMismatch;
        const tree=c.ts_parser_parse_string(parser,null,input.ptr,@intCast(input.len)) orelse return error.OutOfMemory;errdefer c.ts_tree_delete(tree);
        if(c.ts_node_has_error(c.ts_tree_root_node(tree)))return error.InvalidTypeScriptInput;
        return .{.parser=parser,.tree=tree};
    }
    fn deinit(self:Tree)void{c.ts_tree_delete(self.tree);c.ts_parser_delete(self.parser);}
};
const Plan=struct{
    gpa:std.mem.Allocator,input:[]const u8,root:c.TSNode,
    edits:std.ArrayList(Edit)=.empty,names:std.ArrayList([]u8)=.empty,
    fn deinit(self:*Plan)void{for(self.edits.items)|e|self.gpa.free(e.replacement);self.edits.deinit(self.gpa);for(self.names.items)|name|self.gpa.free(name);self.names.deinit(self.gpa);}
    fn text(self:*Plan,node:c.TSNode)[]const u8{return self.input[start(node)..end(node)];}
    fn edit(self:*Plan,a:usize,b:usize,value:[]const u8)!void{const copy=try self.gpa.dupe(u8,value);errdefer self.gpa.free(copy);try self.edits.append(self.gpa,.{.start=a,.end=b,.replacement=copy});}
    fn hasName(self:*Plan,node:c.TSNode,name:[]const u8,depth:usize)!bool{
        if(depth>256)return error.TypeScriptNestingLimit;
        if((is(node,"identifier") or is(node,"type_identifier") or is(node,"shorthand_property_identifier_pattern")) and std.mem.eql(u8,self.text(node),name))return true;
        for(0..c.ts_node_named_child_count(node))|i|if(try self.hasName(c.ts_node_named_child(node,@intCast(i)),name,depth+1))return true;
        return false;
    }
    fn fresh(self:*Plan,base:[]const u8)![]const u8{
        for(0..4096)|i|{
            const name=if(i==0)try self.gpa.dupe(u8,base) else try std.fmt.allocPrint(self.gpa,"{s}{d}",.{base,i+1});
            errdefer self.gpa.free(name);
            var found=try self.hasName(self.root,name,0);for(self.names.items)|other|{if(std.mem.eql(u8,other,name))found=true;}
            if(found){self.gpa.free(name);continue;}
            try self.names.append(self.gpa,name);return name;
        }
        return error.UnsupportedBabelTemporaryNameBudget;
    }
    fn output(self:*Plan)![]u8{
        std.mem.sort(Edit,self.edits.items,{},struct{fn less(_:void,a:Edit,b:Edit)bool{return if(a.start==b.start)a.end<b.end else a.start<b.start;}}.less);
        var result:std.Io.Writer.Allocating=.init(self.gpa);defer result.deinit();var offset:usize=0;
        for(self.edits.items)|e|{if(e.start<offset)return error.OverlappingBabelSyntaxEdits;try result.writer.writeAll(self.input[offset..e.start]);try result.writer.writeAll(e.replacement);offset=e.end;}
        try result.writer.writeAll(self.input[offset..]);return result.toOwnedSlice();
    }
};
fn decorate(plan:*Plan,node:c.TSNode,depth:usize)!void{
    if(depth>256)return error.TypeScriptNestingLimit;
    if(is(node,"class_declaration")){
        const parent=c.ts_node_parent(node);const container=if(is(parent,"export_statement"))parent else node;
        var class_decorators:std.ArrayList(c.TSNode)=.empty;defer class_decorators.deinit(plan.gpa);
        if(is(parent,"export_statement"))for(0..c.ts_node_named_child_count(parent))|i|{const child=c.ts_node_named_child(parent,@intCast(i));if(is(child,"decorator"))try class_decorators.append(plan.gpa,child);};
        for(0..c.ts_node_named_child_count(node))|i|{const child=c.ts_node_named_child(node,@intCast(i));if(is(child,"decorator"))try class_decorators.append(plan.gpa,child);}
        if(class_decorators.items.len!=0){
            const body=field(node,"body");if(try containsDecorator(body,0))return error.UnsupportedBabelMemberDecorator;
            const class_name=field(node,"name");if(c.ts_node_is_null(class_name))return error.UnsupportedBabelAnonymousDecoratedClass;
            const class_token=token(node,"class") orelse return error.UnsupportedBabelClassSyntax;
            const temporary=try plan.fresh("_class");
            var declaration:std.Io.Writer.Allocating=.init(plan.gpa);defer declaration.deinit();
            var prefix:std.Io.Writer.Allocating=.init(plan.gpa);defer prefix.deinit();
            var expressions:std.ArrayList([]const u8)=.empty;defer expressions.deinit(plan.gpa);
            try declaration.writer.print("var {s}",.{temporary});
            // Babel first evaluates every non-Identifier decorator expression
            // in source order, then applies the resulting decorators in reverse.
            for(class_decorators.items)|dec|{
                const expression=c.ts_node_named_child(dec,0);
                if(is(expression,"identifier")){try expressions.append(plan.gpa,plan.text(expression));}
                else{const alias=try plan.fresh("_dec");try declaration.writer.print(",{s}",.{alias});try prefix.writer.print("{s}=({s}),",.{alias,plan.text(expression)});try expressions.append(plan.gpa,alias);}
            }
            var value=try plan.gpa.dupe(u8,plan.input[start(class_token)..end(node)]);defer plan.gpa.free(value);
            var i=expressions.items.len;while(i>0){i-=1;const wrapped=try std.fmt.allocPrint(plan.gpa,"({s}({s}=({s}))||{s})",.{expressions.items[i],temporary,value,temporary});plan.gpa.free(value);value=wrapped;}
            var result:std.Io.Writer.Allocating=.init(plan.gpa);defer result.deinit();
            try result.writer.writeAll(declaration.written());try result.writer.writeByte(';');
            const exported=is(parent,"export_statement");const default_export=exported and token(parent,"default")!=null;
            if(exported and !default_export)try result.writer.writeAll("export ");
            try result.writer.print("let {s}=({s}{s});",.{plan.text(class_name),prefix.written(),value});
            if(default_export)try result.writer.print("export{{{s} as default}};",.{plan.text(class_name)});
            try plan.edit(start(container),end(container),result.written());return;
        }
    }
    if(is(node,"decorator"))return error.UnsupportedBabelMemberDecorator;
    for(0..c.ts_node_named_child_count(node))|i|try decorate(plan,c.ts_node_named_child(node,@intCast(i)),depth+1);
}
fn containsDecorator(node:c.TSNode,depth:usize)!bool{
    if(depth>256)return error.TypeScriptNestingLimit;if(is(node,"decorator"))return true;
    for(0..c.ts_node_named_child_count(node))|i|if(try containsDecorator(c.ts_node_named_child(node,@intCast(i)),depth+1))return true;
    return false;
}
fn decorators(gpa:std.mem.Allocator,input:[]const u8)![]u8{
    const tree=try Tree.init(input);defer tree.deinit();var plan:Plan=.{.gpa=gpa,.input=input,.root=c.ts_tree_root_node(tree.tree)};defer plan.deinit();
    try decorate(&plan,plan.root,0);return plan.output();
}
fn resourceKind(node:c.TSNode)bool{return (is(node,"lexical_declaration") or is(node,"variable_declaration") or is(node,"using_declaration")) and token(node,"using")!=null;}
fn nestedResource(node:c.TSNode,depth:usize)!bool{
    if(depth>256)return error.TypeScriptNestingLimit;if(resourceKind(node))return true;
    for(0..c.ts_node_named_child_count(node))|i|if(try nestedResource(c.ts_node_named_child(node,@intCast(i)),depth+1))return true;return false;
}
pub fn prepare(gpa:std.mem.Allocator,input:[]const u8,typescript:bool)!Prepared{
    // Every writer is memory-backed; a failed write is allocator failure.
    return prepareBody(gpa,input,typescript) catch |err| return if(err==error.WriteFailed)error.OutOfMemory else err;
}
fn prepareBody(gpa:std.mem.Allocator,input:[]const u8,typescript:bool)!Prepared{
    const decorated=if(typescript)try decorators(gpa,input) else try gpa.dupe(u8,input);defer gpa.free(decorated);
    const tree=try Tree.init(decorated);defer tree.deinit();const root=c.ts_tree_root_node(tree.tree);
    var plan:Plan=.{.gpa=gpa,.input=decorated,.root=root};defer plan.deinit();
    var context:?[]const u8=null;var helper:?[]const u8=null;var asynchronous=false;
    for(0..c.ts_node_named_child_count(root))|i|{
        const item=c.ts_node_named_child(root,@intCast(i));
        if(!resourceKind(item)){if(try nestedResource(item,0))return error.UnsupportedBabelNestedResourceScope;continue;}
        if(context==null){context=try plan.fresh("_usingCtx");helper=try plan.fresh("_usingCtx2");}
        const using=token(item,"using").?;const awaited=token(item,"await");asynchronous=asynchronous or awaited!=null;
        try plan.edit(if(awaited)|a|start(a) else start(using),end(using),"var");
        for(0..c.ts_node_named_child_count(item))|j|{
            const declaration=c.ts_node_named_child(item,@intCast(j));if(!is(declaration,"variable_declarator"))continue;
            const value=field(declaration,"value");if(c.ts_node_is_null(value))return error.UnsupportedBabelUsingInitializer;
            if(is(value,"arrow_function") or ((is(value,"function_expression") or is(value,"class")) and c.ts_node_is_null(field(value,"name"))))return error.UnsupportedBabelAnonymousUsingName;
            const prefix=try std.fmt.allocPrint(gpa,"{s}.{s}(",.{context.?,if(awaited!=null)"a" else "u"});defer gpa.free(prefix);
            try plan.edit(start(value),start(value),prefix);try plan.edit(end(value),end(value),")");
        }
    }
    if(context!=null)for(0..c.ts_node_named_child_count(root))|i|{
        const item=c.ts_node_named_child(root,@intCast(i));
        const declaration=if(is(item,"export_statement"))field(item,"declaration") else item;
        if(is(declaration,"lexical_declaration") and !resourceKind(declaration)){
            const keyword=field(declaration,"kind");try plan.edit(start(keyword),end(keyword),"var");
        }else if(is(declaration,"class_declaration")){
            const name=field(declaration,"name");const keyword=token(declaration,"class") orelse return error.UnsupportedBabelClassSyntax;
            const prefix=try std.fmt.allocPrint(gpa,"var {s}=",.{plan.text(name)});defer gpa.free(prefix);
            try plan.edit(start(keyword),start(keyword),prefix);try plan.edit(end(declaration),end(declaration),";");
        }
    };
    const output=try plan.output();errdefer gpa.free(output);
    var resource:?Resource=null;
    if(context)|name|{const ctx=try gpa.dupe(u8,name);errdefer gpa.free(ctx);const fn_name=try gpa.dupe(u8,helper.?);resource=.{.context=ctx,.helper=fn_name,.asynchronous=asynchronous};}
    return .{.source=output,.resource=resource};
}
