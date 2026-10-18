//! Private consumed ignore7.0.8 factory/add/ignores. MIT kael.
//! Actual gitwildmatch compiler and ordinary matcher/rule/cache objects.
const v = @import("native_sdk_ignore708_values.zig");
const compiler = @import("native_sdk_ignore708_compile.zig");
const classes = @import("native_class.zig");
const Scope = v.Scope;
const c = v.c;
const cache_key = "\x00sdk-actual-ignore708-default";
const initializing_key = "\x00sdk-actual-ignore708-initializing";
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return v.arg(args,index); }
fn constructor(s: *Scope, name: [:0]const u8, length: c_int, comptime body: v.Body, context: c.JSValue) !c.JSValue {
    const prototype=try s.object();
    return s.own(try classes.constructor(s.engine,name,length,prototype,v.adapt(body),&.{context}));
}
fn initialize(s: *Scope) !c.JSValue {
    const context=try s.object(); const symbol=try s.global("Symbol");
    const key=if(c.JS_IsUndefined(symbol)) try s.text("node-ignore") else try s.invoke(try s.global("Symbol"),"for",&.{try s.text("node-ignore")});
    try s.put(context,"keyIgnore",key);
    const process=try s.global("process"); const windows=!c.JS_IsUndefined(process) and try v.eq(s,try s.get(try s.global("process"),"platform"),"win32");
    try s.put(context,"windows",c.pi_js_bool(s.engine.context,@intFromBool(windows)));
    const literals = .{
        .{"blank","^ +$",""}, .{"invalidBackslash","(?:[^\\\\]|^)\\\\$",""},
        .{"leadingBang","^\\\\!",""}, .{"leadingHash","^\\\\#",""}, .{"splitLines","\\r?\\n","g"},
        .{"windowsNamespace","^\\\\\\\\\\?\\\\",""}, .{"windowsInvalid","[\"<>|\\u0000-\\u001F]+","u"},
        .{"windowsSeparators","\\\\","g"}, .{"windowsAbsolute","^[a-z]:\\/","i"},
    };
    inline for(literals) |entry| try s.put(context,entry[0],try v.literal(s,entry[1],entry[2]));
    try compiler.init(s,context);
    const rule=try constructor(s,"IgnoreRule",6,ruleConstruct,context); try s.put(context,"Rule",rule);
    const rule_proto=try s.get(rule,"prototype");
    try v.getter(s,rule_proto,"_basenameOnly","get _basenameOnly",ruleBasename,&.{context});
    try v.getter(s,rule_proto,"regex","get regex",ruleRegex,&.{context});
    try v.getter(s,rule_proto,"checkRegex","get checkRegex",ruleCheckRegex,&.{context});
    try v.method(s,rule_proto,"_make",2,ruleMake,&.{context});
    const manager=try constructor(s,"RuleManager",1,managerConstruct,context); try s.put(context,"RuleManager",manager);
    const manager_proto=try s.get(manager,"prototype");
    try v.method(s,manager_proto,"_add",1,managerAddOne,&.{context}); try v.method(s,manager_proto,"add",1,managerAdd,&.{context}); try v.method(s,manager_proto,"test",3,managerTest,&.{context});
    const ignore=try constructor(s,"Ignore",0,ignoreConstruct,context); try s.put(context,"Ignore",ignore);
    const ignore_proto=try s.get(ignore,"prototype");
    try v.method(s,ignore_proto,"_initCache",0,initCache,&.{context}); try v.method(s,ignore_proto,"add",1,ignoreAdd,&.{context});
    try v.method(s,ignore_proto,"_test",3,ignoreTest,&.{context}); try v.method(s,ignore_proto,"_t",3,ignoreT,&.{context}); try v.method(s,ignore_proto,"ignores",1,ignores,&.{context});
    const factory=try s.own(try v.f.createArrow(s.engine,"factory",1,v.adapt(factoryBody),&.{context}));
    try s.set(factory,"default",factory);
    return v.dup(s,factory);
}
fn createManaged(engine: *v.em.Engine, claimed: *bool) !c.JSValue {
    var entry: Scope=.{.engine=engine}; _=try entry.raw(c.pi_js_undefined(),engine.native_allocation_generation);
    if(engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context,cached);
    if(engine.native_module_values.contains(initializing_key)) return error.NativeIgnore708InitializationInProgress;
    try engine.native_module_values.put(engine.gpa,initializing_key,c.pi_js_bool(engine.context,1)); claimed.*=true;
    var s:Scope=.{.engine=engine}; return v.owned.finishValue(&s,initialize(&s));
}
pub fn createDefault(engine: *v.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed+=1; defer engine.native_exception_diagnostics_suppressed-=1;
    var invocation:v.em.Engine.NativeInvocation= .{}; engine.enterNativeInvocation(&invocation);
    var claimed=false; defer if(claimed){_=engine.native_module_values.remove(initializing_key);};
    var boundary:Scope=.{.engine=engine};
    const result=createManaged(engine,&claimed) catch |err| return boundary.raw(engine.leaveNativeInvocation(&invocation,@import("native_sdk.zig").fail(engine,err)),engine.native_allocation_generation);
    const value=try boundary.raw(engine.leaveNativeInvocation(&invocation,result),engine.native_allocation_generation);
    if(claimed){const retained=v.dup(&boundary,value); engine.native_module_values.put(engine.gpa,cache_key,retained) catch |err| {var completion=v.owned.Completion.initValue(engine,err); completion.release(value); completion.release(retained); return completion.finishValue();};}
    return value;
}
fn factoryBody(s:*Scope,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue { return v.dup(s,try s.construct(try s.get(roots[0],"Ignore"),&.{arg(args,0)})); }
fn ignoreConstruct(s:*Scope,target:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    const self=try v.objectFromTarget(s,target); const options=if(c.JS_IsUndefined(arg(args,0)))try s.object() else arg(args,0);
    const lower=try s.get(options,"ignorecase"); const ignorecase=if(c.JS_IsUndefined(lower))c.pi_js_bool(s.engine.context,1) else lower;
    const upper=try s.get(options,"ignoreCase"); const ignore_case=if(c.JS_IsUndefined(upper))ignorecase else upper;
    const relative=try s.get(options,"allowRelativePaths"); const allow=if(c.JS_IsUndefined(relative))c.pi_js_bool(s.engine.context,0) else relative;
    _=try v.define(s,self,try s.get(roots[0],"keyIgnore"),c.pi_js_bool(s.engine.context,1));
    try s.set(self,"_rules",try s.construct(try s.get(roots[0],"RuleManager"),&.{ignore_case}));
    try s.set(self,"_strictPathCheck",c.pi_js_bool(s.engine.context,@intFromBool(!s.truthy(allow))));
    _=try s.invoke(self,"_initCache",&.{}); return v.dup(s,self);
}
fn managerConstruct(s:*Scope,target:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue {
    const self=try v.objectFromTarget(s,target); try s.set(self,"_ignoreCase",arg(args,0)); try s.set(self,"_rules",try s.array()); try s.set(self,"_basenameCount",v.num(s,0)); return v.dup(s,self);
}
fn ruleConstruct(s:*Scope,target:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue {
    const self=try v.objectFromTarget(s,target); try s.set(self,"pattern",arg(args,0)); try s.set(self,"mark",arg(args,1)); try s.set(self,"negative",arg(args,4));
    _=try v.namedDefine(s,self,"body",arg(args,2)); _=try v.namedDefine(s,self,"ignoreCase",arg(args,3)); _=try v.namedDefine(s,self,"regexPrefix",arg(args,5)); return v.dup(s,self);
}
fn initCache(s:*Scope,self:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue { try s.set(self,"_ignoreCache",try v.nullObject(s)); try s.set(self,"_testCache",try v.nullObject(s)); return c.pi_js_undefined(); }
fn ignoreAdd(s:*Scope,self:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue {
    if(s.truthy(try s.invoke(try s.get(self,"_rules"),"add",&.{arg(args,0)})))_=try s.invoke(self,"_initCache",&.{}); return v.dup(s,self);
}
fn splitPattern(s:*Scope,pattern:c.JSValue,context:c.JSValue)!c.JSValue {
    const split=try s.get(pattern,"split"); const parts=try s.call(split,pattern,&.{try s.get(context,"splitLines")}); const filter=try s.get(parts,"filter"); return s.call(filter,parts,&.{try s.global("Boolean")});
}
fn managerAdd(s:*Scope,self:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    try s.set(self,"_added",c.pi_js_bool(s.engine.context,0)); const pattern=arg(args,0); const input=if(c.JS_IsString(pattern))try splitPattern(s,pattern,roots[0]) else pattern;
    const array=try s.invoke(try s.global("Array"),"isArray",&.{input}); const list=if(s.truthy(array))input else item: {const out=try s.array(); try s.index(out,0,input); break :item out;};
    const for_each=try s.get(list,"forEach"); const add=try s.get(self,"_add"); _=try s.call(for_each,list,&.{add,self}); return v.dup(s,try s.get(self,"_added"));
}
fn checkPattern(s:*Scope,pattern:c.JSValue,context:c.JSValue)!bool {
    return s.truthy(pattern) and c.JS_IsString(pattern) and !try v.regex(s,context,"blank",pattern) and !try v.regex(s,context,"invalidBackslash",pattern) and !s.equal(try s.invoke(pattern,"indexOf",&.{try s.text("#")}),v.num(s,0));
}
fn matchesBasename(s:*Scope,body:c.JSValue)!bool { const index=try s.invoke(body,"indexOf",&.{try s.text("/")}); return try s.compare(.less,index,v.num(s,0)) or s.equal(index,try s.binary(.subtract,try v.len(s,body),v.num(s,1))); }
fn createRule(s:*Scope,object:c.JSValue,ignore_case:c.JSValue,context:c.JSValue)!c.JSValue {
    const pattern=try s.get(object,"pattern"); const mark=try s.get(object,"mark"); var negative=false; var body=pattern;
    if(s.equal(try s.invoke(body,"indexOf",&.{try s.text("!")}),v.num(s,0))){negative=true; body=try s.invoke(body,"substr",&.{v.num(s,1)});}
    const one=try s.get(body,"replace"); body=try s.call(one,body,&.{try s.get(context,"leadingBang"),try s.text("!")});
    const two=try s.get(body,"replace"); body=try s.call(two,body,&.{try s.get(context,"leadingHash"),try s.text("#")});
    const prefix=try compiler.prefix(s,body,context); return s.construct(try s.get(context,"Rule"),&.{pattern,mark,body,ignore_case,c.pi_js_bool(s.engine.context,@intFromBool(negative)),prefix});
}
fn managerAddOne(s:*Scope,self:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    var pattern=arg(args,0); const context=roots[0];
    if(s.truthy(pattern) and s.truthy(try s.getKey(pattern,try s.get(context,"keyIgnore")))){
        const before=try s.get(self,"_rules"); const concatenate=try s.get(before,"concat"); const nested=try s.get(try s.get(pattern,"_rules"),"_rules"); try s.set(self,"_rules",try s.call(concatenate,before,&.{nested}));
        const count=try s.get(self,"_basenameCount"); const incoming=try s.get(try s.get(pattern,"_rules"),"_basenameCount"); try s.set(self,"_basenameCount",try s.binary(.add,count,incoming)); try s.set(self,"_added",c.pi_js_bool(s.engine.context,1)); return c.pi_js_undefined();
    }
    if(c.JS_IsString(pattern)){const item=try s.object(); try s.put(item,"pattern",pattern); pattern=item;}
    if(try checkPattern(s,try s.get(pattern,"pattern"),context)){
        const rule=try createRule(s,pattern,try s.get(self,"_ignoreCase"),context); try s.set(self,"_added",c.pi_js_bool(s.engine.context,1)); _=try s.invoke(try s.get(self,"_rules"),"push",&.{rule});
        if(try matchesBasename(s,try s.get(rule,"body")))try s.set(self,"_basenameCount",try v.increment(s,try s.get(self,"_basenameCount")));
    }
    return c.pi_js_undefined();
}
fn ruleBasename(s:*Scope,self:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue { return v.dup(s,try v.namedDefine(s,self,"_basenameOnly",c.pi_js_bool(s.engine.context,@intFromBool(try matchesBasename(s,try s.get(self,"body")))))); }
fn cachedRegex(s:*Scope,self:c.JSValue,mode:[]const u8)!c.JSValue {
    const key=try s.concat(try s.text("_"),try s.text(mode)); if(s.truthy(try s.getKey(self,key)))return s.getKey(self,key);
    return s.invoke(self,"_make",&.{try s.text(mode),key});
}
fn ruleRegex(s:*Scope,self:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue { return v.dup(s,try cachedRegex(s,self,"regex")); }
fn ruleCheckRegex(s:*Scope,self:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue { return v.dup(s,try cachedRegex(s,self,"checkRegex")); }
fn ruleMake(s:*Scope,self:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    const prefix=try s.get(self,"regexPrefix"); const replace=try s.get(prefix,"replace"); const context=roots[0];
    const replacer=try s.getKey(try s.get(context,"trailingReplacers"),arg(args,0));
    const text=try s.call(replace,prefix,&.{try s.get(context,"replaceTrailing"),replacer}); const pinned=try compiler.pin(s,text,context);
    const expression=if(s.truthy(try s.get(self,"ignoreCase")))try s.construct(try s.global("RegExp"),&.{pinned,try s.text("i")}) else try s.construct(try s.global("RegExp"),&.{pinned});
    return v.dup(s,try v.define(s,self,arg(args,1),expression));
}
fn basename(s:*Scope,path:c.JSValue)!c.JSValue {
    const end=try s.binary(.subtract,try v.len(s,path),v.num(s,1)); const last_index=try s.get(path,"lastIndexOf");
    const at=if(try v.eq(s,try s.getKey(path,end),"/"))try s.binary(.subtract,end,v.num(s,1)) else end;
    const index=try s.call(last_index,path,&.{try s.text("/"),at});
    if(try s.compare(.less,index,v.num(s,0)))return path; const method=try s.get(path,"slice"); return s.call(method,path,&.{try s.binary(.add,index,v.num(s,1))});
}
fn managerTest(s:*Scope,self:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue {
    const path=arg(args,0); const check_unignored=arg(args,1); const mode=arg(args,2); var ignored=c.pi_js_bool(s.engine.context,0); var unignored=ignored; var matched=c.pi_js_undefined();
    const rules=try s.get(self,"_rules"); const length=try v.len(s,rules); const shortcut=try s.compare(.greater_equal,try s.binary(.multiply,try s.get(self,"_basenameCount"),v.num(s,2)),length);
    const name=if(shortcut)try basename(s,path) else path; var index:usize=0;
    while(try s.compare(.less,v.num(s,index),length)) : (index+=1) {
        try s.check(index+1); const rule=try v.at(s,rules,index); const negative=try s.get(rule,"negative");
        const skip=(s.equal(unignored,negative) and !s.equal(ignored,unignored)) or (s.truthy(negative) and !s.truthy(ignored) and !s.truthy(unignored) and !s.truthy(check_unignored)); if(skip)continue;
        const expression=try s.getKey(rule,mode); const test_method=try s.get(expression,"test"); const input=if(shortcut and s.truthy(try s.get(rule,"_basenameOnly")))name else path;
        if(s.truthy(try s.call(test_method,expression,&.{input}))){ignored=c.pi_js_bool(s.engine.context,@intFromBool(!s.truthy(negative))); unignored=negative; matched=if(s.truthy(negative))c.pi_js_undefined() else rule;}
    }
    const result=try s.object(); try s.put(result,"ignored",ignored); try s.put(result,"unignored",unignored); if(s.truthy(matched))try s.put(result,"rule",matched); return v.dup(s,result);
}
fn convert(s:*Scope,path:c.JSValue,context:c.JSValue)!c.JSValue {
    if(!s.truthy(try s.get(context,"windows")))return path;
    if(try v.regex(s,context,"windowsNamespace",path) or try v.regex(s,context,"windowsInvalid",path))return path;
    const replace=try s.get(path,"replace"); return s.call(replace,path,&.{try s.get(context,"windowsSeparators"),try s.text("/")});
}
fn notRelative(s:*Scope,path:c.JSValue,context:c.JSValue)!bool {
    if(s.truthy(try s.get(context,"windows")) and try v.regex(s,context,"windowsAbsolute",path))return true;
    const first=try s.invoke(path,"charCodeAt",&.{v.num(s,0)}); if(s.equal(first,v.num(s,47)))return true; if(!s.equal(first,v.num(s,46)))return false;
    if(s.equal(try v.len(s,path),v.num(s,1)))return true; const second=try s.invoke(path,"charCodeAt",&.{v.num(s,1)}); if(s.equal(second,v.num(s,47)))return true; if(!s.equal(second,v.num(s,46)))return false;
    return s.equal(try v.len(s,path),v.num(s,2)) or s.equal(try s.invoke(path,"charCodeAt",&.{v.num(s,2)}),v.num(s,47));
}
fn checkPath(s:*Scope,path:c.JSValue,original:c.JSValue,strict:bool,context:c.JSValue)!void {
    if(!c.JS_IsString(path)) { if(!strict)return; const text=try s.concat(try s.concat(try s.text("path must be a string, but got `"),try v.string(s,original)),try s.text("`")); return v.throwType(s,"TypeError",text); }
    if(!s.truthy(path)){if(!strict)return; return v.throwType(s,"TypeError",try s.text("path must not be empty"));}
    if(try notRelative(s,path,context)){if(!strict)return; const text=try s.concat(try s.concat(try s.text("path should be a `path.relative()`d string, but got \""),try v.string(s,original)),try s.text("\"")); return v.throwType(s,"RangeError",text);}
}
fn parent(s:*Scope,path:c.JSValue)!c.JSValue {
    const first=try s.invoke(path,"charCodeAt",&.{v.num(s,0)});
    if(s.equal(first,v.num(s,47)) or try s.compare(.greater_equal,try s.invoke(path,"indexOf",&.{try s.text("//")}),v.num(s,0))){
        const parts=try s.invoke(path,"split",&.{try s.text("/")}); const filter=try s.get(parts,"filter"); const slices=try s.call(filter,parts,&.{try s.global("Boolean")}); _=try s.invoke(slices,"pop",&.{});
        if(!s.truthy(try v.len(s,slices)))return s.text(""); return s.concat(try s.invoke(slices,"join",&.{try s.text("/")}),try s.text("/"));
    }
    const end=try s.binary(.subtract,try v.len(s,path),v.num(s,1)); const last_index=try s.get(path,"lastIndexOf");
    const start=if(s.equal(try s.invoke(path,"charCodeAt",&.{end}),v.num(s,47)))try s.binary(.subtract,end,v.num(s,1)) else end;
    const cut=try s.call(last_index,path,&.{try s.text("/"),start}); if(try s.compare(.less,cut,v.num(s,0)))return s.text("");
    const slice=try s.get(path,"slice"); return s.call(slice,path,&.{v.num(s,0),try s.binary(.add,cut,v.num(s,1))});
}
fn ignoreTest(s:*Scope,self:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue {
    const original=arg(args,0); const path=if(s.truthy(original))try convert(s,original,roots[0]) else original;
    try checkPath(s,path,original,s.truthy(try s.get(self,"_strictPathCheck")),roots[0]); return v.dup(s,try s.invoke(self,"_t",&.{path,arg(args,1),arg(args,2)}));
}
fn ignoreT(s:*Scope,self:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue {
    const path=arg(args,0); const cache=arg(args,1); const check_unignored=arg(args,2); if(try s.hasKey(cache,path))return v.dup(s,try s.getKey(cache,path));
    const above=try parent(s,path); const parent_result=if(s.truthy(above))try s.invoke(self,"_t",&.{above,cache,check_unignored}) else c.pi_js_undefined();
    const result=if(s.truthy(parent_result) and s.truthy(try s.get(parent_result,"ignored")))parent_result else try s.invoke(try s.get(self,"_rules"),"test",&.{path,check_unignored,try s.text("regex")});
    try s.setKey(cache,path,result); return v.dup(s,result);
}
fn ignores(s:*Scope,self:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue {
    const test_method=try s.get(self,"_test"); const result=try s.call(test_method,self,&.{arg(args,0),try s.get(self,"_ignoreCache"),c.pi_js_bool(s.engine.context,0)}); return v.dup(s,try s.get(result,"ignored"));
}
