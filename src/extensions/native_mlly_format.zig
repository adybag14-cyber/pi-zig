//! Consumed import-meta-resolve4.2 get-format protocol dispatch and handlers.
//! No Node default resolver or invented MIME/file-format fallback is used.
const m=@import("native_mlly_values.zig");
const reader=@import("native_mlly_package_reader.zig");
const errors=@import("native_mlly_errors.zig");
const c=m.c;
const Scope=m.Scope;
fn arg(args:[]const c.JSValue,index:usize)c.JSValue{return if(index<args.len)args[index] else c.pi_js_undefined();}
pub fn initialize(s:*Scope,owner:c.JSValue)!void{
    const formats=try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context,c.pi_js_null())));
    inline for(.{.{".cjs","commonjs"},.{".js","module"},.{".json","json"},.{".mjs","module"}})|entry|try m.define(s,formats,entry[0],try s.text(entry[1]));
    try m.define(s,owner,"extensionFormatMap",formats);
    const handlers=try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context,c.pi_js_null())));
    const data=try s.own(try m.functions.create(s.engine,"getDataProtocolModuleFormat",1,dataCall,&.{owner}));
    const file=try s.own(try m.functions.create(s.engine,"getFileProtocolModuleFormat",3,fileCall,&.{owner}));
    const http=try s.own(try m.functions.create(s.engine,"getHttpProtocolModuleFormat",0,httpCall,&.{}));
    const node=try s.own(try m.functions.createMethod(s.engine,"node:",0,nodeCall,&.{}));
    try m.define(s,handlers,"data:",data);try m.define(s,handlers,"file:",file);try m.define(s,handlers,"http:",http);try m.define(s,handlers,"https:",http);try m.define(s,handlers,"node:",node);
    try m.define(s,owner,"protocolHandlers",handlers);
}
pub fn defaultGetFormatWithoutErrors(context:m.Context,s:*Scope,url:c.JSValue,input_context:c.JSValue) anyerror!c.JSValue{
    const protocol=try s.get(url,"protocol");
    const handlers=try context.get(s,"protocolHandlers");
    if(!try context.own(s,handlers,protocol))return c.pi_js_null();
    const handler=try m.at(s,handlers,protocol);
    const format=try s.call(handler,handlers,&.{url,input_context,c.pi_js_bool(s.engine.context,1)});
    return if(s.truthy(format))format else c.pi_js_null();
}
fn nodeCall(engine:*m.v.em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{return engine.checked(c.JS_NewString(engine.context,"builtin"));}
fn httpCall(_: *m.v.em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{return c.pi_js_undefined();}
fn dataCall(engine:*m.v.em.Engine,_:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue) anyerror!c.JSValue{
    var s:Scope=.{.engine=engine};defer s.deinit();
    const regex=try m.regex(&s,"^([^/]+/[^;,]+)[^,]*?(;base64)?,","");const exec=try s.get(regex,"exec");
    const matched=try s.call(exec,regex,&.{try s.get(arg(args,0),"pathname")});
    const destructured=if(s.truthy(matched))matched else try m.array(&s,&.{c.pi_js_null(),c.pi_js_null(),c.pi_js_null()});
    const mime=try m.at(&s,destructured,m.integer(&s,1));
    if(s.truthy(mime)){
        const mime_regex=try m.regex(&s,"\\s*(text|application)/javascript\\s*(;\\s*charset=utf-?8\\s*)?","i");
        if(s.truthy(try s.invoke(mime_regex,"test",&.{mime})))return engine.checked(c.JS_NewString(engine.context,"module"));
    }
    if(try m.equal(&s,mime,"application/json"))return engine.checked(c.JS_NewString(engine.context,"json"));
    return c.pi_js_null();
}
fn extension(s:*Scope,url:c.JSValue) anyerror!c.JSValue{
    const pathname=try s.get(url,"pathname");
    var index=c.JS_DupValue(s.engine.context,try s.get(pathname,"length"));defer s.engine.freeValue(index);
    var steps:usize=0;
    while(true){
        // Post-decrement's old completion is ToNumeric(index), not the raw
        // string/object originally read from pathname.length. Convert once so
        // a live valueOf/Symbol.toPrimitive also runs only once.
        const previous=try s.engine.checked(c.JS_PiToNumeric(s.engine.context,index));
        defer s.engine.freeValue(previous);
        const next=try s.engine.checked(c.JS_PiDecrement(s.engine.context,previous));
        s.engine.freeValue(index);index=next;
        if(!s.truthy(previous))break;
        try m.budget(s.engine,&steps);
        var step:Scope=.{.engine=s.engine};defer step.deinit();
        const code=try step.invoke(pathname,"codePointAt",&.{index});
        if(step.equal(code,m.integer(&step,47)))return s.text("");
        if(step.equal(code,m.integer(&step,46))){
            const code_point=try step.get(pathname,"codePointAt");
            const before=try step.call(code_point,pathname,&.{try m.binary(&step,1,index,m.integer(&step,1))});
            const value=if(step.equal(before,m.integer(&step,47)))try step.text("") else try step.invoke(pathname,"slice",&.{index});
            return s.own(c.JS_DupValue(s.engine.context,value));
        }
    }
    return s.text("");
}
fn fileCall(engine:*m.v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue) anyerror!c.JSValue{
    var s:Scope=.{.engine=engine};defer s.deinit();const context:m.Context=.{.engine=engine,.owner=roots[0]};const url=arg(args,0);
    const value=try extension(&s,url);
    if(try m.equal(&s,value,".js")){
        const kind=try s.get(try reader.getPackageScopeConfig(context,&s,url),"type");
        return c.JS_DupValue(engine.context,if(!try m.equal(&s,kind,"none"))kind else try s.text("commonjs"));
    }
    if(try m.equal(&s,value,"")){
        const kind=try s.get(try reader.getPackageScopeConfig(context,&s,url),"type");
        return engine.checked(c.JS_NewString(engine.context,if(try m.equal(&s,kind,"none") or try m.equal(&s,kind,"commonjs"))"commonjs" else "module"));
    }
    const format=try m.at(&s,try context.get(&s,"extensionFormatMap"),value);if(s.truthy(format))return c.JS_DupValue(engine.context,format);
    if(s.truthy(arg(args,2)))return c.pi_js_undefined();
    const filepath=try context.file(&s,url);
    return m.throwReason(engine,try errors.create(context,&s,.ERR_UNKNOWN_FILE_EXTENSION,&.{value,filepath}));
}
