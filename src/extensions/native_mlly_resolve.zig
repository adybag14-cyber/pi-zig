//! mlly1.8.2 synchronous resolver and consumed URL bindings. Create once for
//! one Source module lifetime, sharing its real sets/cache/regexes/functions.
//! No package registry installation or runtime loader selection occurs here.
const m=@import("native_mlly_values.zig");
const urls=@import("native_mlly_urls.zig");
const ufo=@import("native_ufo_join_url.zig");
const core=@import("native_mlly_module_resolve.zig");
const c=m.c;
const Scope=m.Scope;
pub const Imports=m.Imports;
fn arg(args:[]const c.JSValue,index:usize)c.JSValue{return if(index<args.len)args[index] else c.pi_js_undefined();}
fn actualUrls(context:m.Context,s:*Scope)!urls.Imports{return .{.file_url_to_path=try context.get(s,"fileURLToPath"),.path_to_file_url=try context.get(s,"pathToFileURL")};}
fn mllyFile(context:m.Context,s:*Scope,value:c.JSValue)!c.JSValue{return urls.fileURLToPath(s,try context.get(s,"fileURLToPath"),value);}
fn mllyURL(context:m.Context,s:*Scope,value:c.JSValue)!c.JSValue{return urls.pathToFileURL(s,try actualUrls(context,s),value);}
fn join(context:m.Context,s:*Scope,base:c.JSValue,extra:c.JSValue)!c.JSValue{return ufo.join(s,try context.get(s,"joinLeadingSlash"),base,&.{extra});}
fn mapURL(engine:*m.v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    const generation=engine.native_allocation_generation;
    return mapBody(engine,args,roots) catch |err| return m.exact(engine,err,generation);
}
fn mapBody(engine:*m.v.em.Engine,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    var s:Scope=.{.engine=engine};defer s.deinit();const context:m.Context=.{.engine=engine,.owner=roots[0]};
    const constructor=try s.global("URL");
    const string=try s.invoke(arg(args,0),"toString",&.{});
    const normalized=try urls.normalizeId(&s,try context.get(&s,"builtinSet"),string);
    return c.JS_DupValue(engine.context,try context.constructURL(&s,constructor,&.{normalized}));
}
fn tryModule(context:m.Context,resolver:*core.Resolver,s:*Scope,id:c.JSValue,url:c.JSValue,conditions:c.JSValue) anyerror!c.JSValue{
    const generation=s.engine.native_allocation_generation;
    return resolver.moduleResolve(s,id,url,conditions,false) catch |err|{
        const exception=try m.caught(s,err,generation);
        const not_found=try context.get(s,"notFound");const has=try s.get(not_found,"has");
        const code=if(m.v.nullish(exception))c.pi_js_undefined() else try s.get(exception,"code");
        if(!s.truthy(try s.call(has,not_found,&.{code})))return m.throwReason(s.engine,exception);
        return c.pi_js_undefined();
    };
}
fn optionsURLs(context:m.Context,s:*Scope,options:c.JSValue) anyerror!c.JSValue{
    const array=try s.global("Array");const is_array=try s.get(array,"isArray");const first_url=try s.get(options,"url");
    const values=if(s.truthy(try s.call(is_array,array,&.{first_url})))try s.get(options,"url") else try m.array(s,&.{try s.get(options,"url")});
    const filter=try s.get(values,"filter");const boolean=try s.global("Boolean");const filtered=try s.call(filter,values,&.{boolean});
    const map=try s.get(filtered,"map");const callback=try s.own(try m.functions.createArrow(s.engine,"",1,mapURL,&.{context.owner}));
    const result=try s.call(map,filtered,&.{callback});
    if(s.equal(try s.get(result,"length"),m.integer(s,0))){
        const push=try s.get(result,"push");const constructor=try s.global("URL");
        const cwd=try s.invoke(try context.get(s,"process"),"cwd",&.{});
        const url=try context.constructURL(s,constructor,&.{try mllyURL(context,s,cwd)});
        _=try s.call(push,result,&.{url});
    }
    return result;
}
fn expandURLs(context:m.Context,s:*Scope,original:c.JSValue) anyerror!c.JSValue{
    const result=try m.collect(s,original);
    var iterator=try m.v.iterator(s,original);defer iterator.deinit();const generation=s.engine.native_allocation_generation;
    expandLoop(context,s,result,&iterator) catch |err| return m.closeAbrupt(s.engine,&iterator,err,generation);
    return result;
}
fn expandLoop(context:m.Context,s:*Scope,result:c.JSValue,iterator:*m.v.js.Iterator) anyerror!void{
    while(try m.advance(s.engine,iterator))|url|{
        var step:Scope=.{.engine=s.engine};defer step.deinit();_=try step.own(url);
        if(!try m.equal(&step,try step.get(url,"protocol"),"file:"))continue;
        const push=try step.get(result,"push");
        const parent=try context.url(&step,try step.text("./"),url);
        const constructor=try step.global("URL");const pathname=try step.get(url,"pathname");const index=try context.constructURL(&step,constructor,&.{try join(context,&step,pathname,try step.text("_index.js")),url});
        const modules=try context.url(&step,try step.text("node_modules"),url);
        _=try step.call(push,result,&.{parent,index,modules});
    }
}
fn extensions(context:m.Context,resolver:*core.Resolver,s:*Scope,id:c.JSValue,url:c.JSValue,conditions:c.JSValue,options:c.JSValue,prefix:c.JSValue) anyerror!c.JSValue{
    const requested=try s.get(options,"extensions");const values=if(s.truthy(requested))requested else try context.get(s,"defaultExtensions");
    var iterator=try m.v.iterator(s,values);defer iterator.deinit();const generation=s.engine.native_allocation_generation;
    return extensionsLoop(context,resolver,s,id,url,conditions,prefix,&iterator) catch |err| return m.closeAbrupt(s.engine,&iterator,err,generation);
}
fn extensionsLoop(context:m.Context,resolver:*core.Resolver,s:*Scope,id:c.JSValue,url:c.JSValue,conditions:c.JSValue,prefix:c.JSValue,iterator:*m.v.js.Iterator) anyerror!c.JSValue{
    while(try m.advance(s.engine,iterator))|extension|{
        var step:Scope=.{.engine=s.engine};defer step.deinit();_=try step.own(extension);
        const candidate=try step.concat(try join(context,&step,id,prefix),extension);
        const result=try tryModule(context,resolver,&step,candidate,url,conditions);
        if(step.truthy(result)){try m.closeNormal(s.engine,iterator);return s.own(c.JS_DupValue(s.engine.context,result));}
    }
    return c.pi_js_undefined();
}
fn prefixes(context:m.Context,resolver:*core.Resolver,s:*Scope,id:c.JSValue,url:c.JSValue,conditions:c.JSValue,options:c.JSValue) anyerror!c.JSValue{
    const values=try m.array(s,&.{try s.text(""),try s.text("/index")});
    var iterator=try m.v.iterator(s,values);defer iterator.deinit();const generation=s.engine.native_allocation_generation;
    return prefixesLoop(context,resolver,s,id,url,conditions,options,&iterator) catch |err| return m.closeAbrupt(s.engine,&iterator,err,generation);
}
fn prefixesLoop(context:m.Context,resolver:*core.Resolver,s:*Scope,id:c.JSValue,url:c.JSValue,conditions:c.JSValue,options:c.JSValue,iterator:*m.v.js.Iterator) anyerror!c.JSValue{
    while(try m.advance(s.engine,iterator))|prefix|{
        var step:Scope=.{.engine=s.engine};defer step.deinit();_=try step.own(prefix);
        const result=try extensions(context,resolver,&step,id,url,conditions,options,prefix);
        if(step.truthy(result)){try m.closeNormal(s.engine,iterator);return s.own(c.JS_DupValue(s.engine.context,result));}
    }
    return c.pi_js_undefined();
}
fn search(context:m.Context,s:*Scope,id:c.JSValue,values:c.JSValue,conditions:c.JSValue,options:c.JSValue) anyerror!c.JSValue{
    var resolver:core.Resolver=.{.context=context};var iterator=try m.v.iterator(s,values);defer iterator.deinit();const generation=s.engine.native_allocation_generation;
    return searchLoop(context,&resolver,s,id,conditions,options,&iterator) catch |err| return m.closeAbrupt(s.engine,&iterator,err,generation);
}
fn searchLoop(context:m.Context,resolver:*core.Resolver,s:*Scope,id:c.JSValue,conditions:c.JSValue,options:c.JSValue,iterator:*m.v.js.Iterator) anyerror!c.JSValue{
    while(try m.advance(s.engine,iterator))|url|{
        var step:Scope=.{.engine=s.engine};defer step.deinit();_=try step.own(url);
        var result=try tryModule(context,resolver,&step,id,url,conditions);
        if(!step.truthy(result))result=try prefixes(context,resolver,&step,id,url,conditions,options);
        if(step.truthy(result)){try m.closeNormal(s.engine,iterator);return s.own(c.JS_DupValue(s.engine.context,result));}
    }
    return c.pi_js_undefined();
}
fn resolve(context:m.Context,s:*Scope,input:c.JSValue,options_input:c.JSValue) anyerror!c.JSValue{
    const generation=s.engine.native_allocation_generation;
    return resolveBody(context,s,input,options_input) catch |err| return m.exact(s.engine,err,generation);
}
fn resolveBody(context:m.Context,s:*Scope,input:c.JSValue,options_input:c.JSValue) anyerror!c.JSValue{
    const options=if(c.JS_IsUndefined(options_input))try s.object() else options_input;var id=input;
    if(!c.JS_IsString(id)){
        const instance=c.JS_IsInstanceOf(s.engine.context,id,try s.global("URL"));if(instance<0)return m.v.js.capture(s.engine);
        if(instance!=0)id=try mllyFile(context,s,id) else{
            const reason=try s.own(try m.v.js.builtin(s.engine,"TypeError",&.{try s.text("input must be a `string` or `URL`")}));return m.throwReason(s.engine,reason);
        }
    }
    if(s.truthy(try s.invoke(try m.regex(s,"(?:node|data|http|https):",""),"test",&.{id})))return id;
    if(s.truthy(try s.invoke(try context.get(s,"builtinSet"),"has",&.{id})))return s.concat(try s.text("node:"),id);
    if(s.truthy(try s.invoke(id,"startsWith",&.{try s.text("file://")})))id=try mllyFile(context,s,id);
    if(s.truthy(try s.call(try context.get(s,"patheIsAbsolute"),c.pi_js_undefined(),&.{id}))){
        const generation=s.engine.native_allocation_generation;
        const fast=fastPath(context,s,id) catch |err| blk:{const exception=try m.caught(s,err,generation);const code=if(m.v.nullish(exception))c.pi_js_undefined() else try s.get(exception,"code");if(!try m.equal(s,code,"ENOENT"))return m.throwReason(s.engine,exception);break :blk c.pi_js_undefined();};
        if(!c.JS_IsUndefined(fast))return fast;
    }
    const first_conditions=try s.get(options,"conditions");
    const conditions=if(s.truthy(first_conditions))blk:{const constructor=try s.global("Set");const values=try s.get(options,"conditions");break :blk try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context,constructor,1,@constCast(&[_]c.JSValue{values}))));} else try context.get(s,"defaultConditions");
    const original_urls=try optionsURLs(context,s,options);const all_urls=try expandURLs(context,s,original_urls);
    const result=try search(context,s,id,all_urls,conditions,options);
    if(!s.truthy(result)){
        const constructor=try s.global("Error");
        var text=try s.concat(try s.text("Cannot find module "),try s.stringify(id));text=try s.concat(text,try s.text(" imported from "));text=try s.concat(text,try s.stringify(try s.invoke(all_urls,"join",&.{try s.text(", ")})));
        const reason=try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context,constructor,1,@constCast(&[_]c.JSValue{text}))));try s.set(reason,"code",try s.text("ERR_MODULE_NOT_FOUND"));return m.throwReason(s.engine,reason);
    }
    return mllyURL(context,s,result);
}
fn fastPath(context:m.Context,s:*Scope,id:c.JSValue) anyerror!c.JSValue{
    const stats=try s.call(try context.get(s,"statSync"),c.pi_js_undefined(),&.{id});
    if(s.truthy(try s.invoke(stats,"isFile",&.{})))return mllyURL(context,s,id);return c.pi_js_undefined();
}
fn resolveCall(engine:*m.v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    const generation=engine.native_allocation_generation;return resolveCallBody(engine,args,roots,false) catch |err| return m.exact(engine,err,generation);
}
fn pathCall(engine:*m.v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    const generation=engine.native_allocation_generation;return resolveCallBody(engine,args,roots,true) catch |err| return m.exact(engine,err,generation);
}
fn resolveCallBody(engine:*m.v.em.Engine,args:[]const c.JSValue,roots:[]const c.JSValue,path:bool)!c.JSValue{
    var s:Scope=.{.engine=engine};defer s.deinit();const context:m.Context=.{.engine=engine,.owner=roots[0]};
    const result=try resolve(context,&s,arg(args,0),arg(args,1));
    return c.JS_DupValue(engine.context,if(path)try mllyFile(context,&s,result) else result);
}
pub fn create(engine:*m.v.em.Engine,imports:Imports)!c.JSValue{
    // Exact builtin inventory is supplied by the real node:module owner. No
    // inferred/placeholder registry and no resolver-normalization collaborator.
    inline for(.{imports.file_url_to_path,imports.path_to_file_url,imports.stat_sync,imports.realpath_sync,imports.pathe_is_absolute,imports.pathe_normalize})|function|if(!c.JS_IsFunction(engine.context,function))return error.NativeMllyActualBindingsRequired;
    if(!c.JS_IsArray(imports.builtin_modules))return error.NativeMllyActualBuiltinModulesArrayRequired;
    var s:Scope=.{.engine=engine};defer s.deinit();const owner=try s.own(try m.initialize(engine,imports));
    try m.define(&s,owner,"joinLeadingSlash",try ufo.moduleRegex(&s));
    const result=try s.own(try urls.create(engine,.{.file_url_to_path=imports.file_url_to_path,.path_to_file_url=imports.path_to_file_url}));
    try m.v.js.define(engine,result,"resolveSync",try m.functions.create(engine,"resolveSync",2,resolveCall,&.{owner}));
    try m.v.js.define(engine,result,"resolvePathSync",try m.functions.create(engine,"resolvePathSync",2,pathCall,&.{owner}));
    return c.JS_DupValue(engine.context,result);
}
