//! ufo1.6.4 joinURL's actual filter/iterator/slash behavior (not pathe.join).
const m=@import("native_mlly_values.zig");
const c=m.c;
const Scope=m.Scope;
fn nonEmpty(engine:*m.v.em.Engine,_:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue) !c.JSValue {
    const value=if(args.len>0)args[0] else c.pi_js_undefined();
    if(c.JS_ToBool(engine.context,value)==0)return c.JS_DupValue(engine.context,value);
    var s:Scope=.{.engine=engine}; defer s.deinit();
    return c.pi_js_bool(engine.context,@intFromBool(!s.equal(value,try s.text("/"))));
}
pub fn join(s:*Scope,regex:c.JSValue,base:c.JSValue,input:[]const c.JSValue) anyerror!c.JSValue {
    const rest=try m.array(s,input); const filter=try s.get(rest,"filter");
    const predicate=try s.own(try m.functions.createArrow(s.engine,"",1,nonEmpty,&.{}));
    const filtered=try s.call(filter,rest,&.{predicate});
    var iterator=try m.v.iterator(s,filtered); defer iterator.deinit();
    const generation=s.engine.native_allocation_generation;
    return loop(s,regex,base,&iterator) catch |err| return m.closeAbrupt(s.engine,&iterator,err,generation);
}
fn loop(s:*Scope,regex:c.JSValue,base:c.JSValue,iterator:*m.v.js.Iterator) anyerror!c.JSValue {
    var url=c.JS_DupValue(s.engine.context,if(s.truthy(base))base else try s.text("")); defer s.engine.freeValue(url);
    while(try m.advance(s.engine,iterator))|value| {
        var step:Scope=.{.engine=s.engine}; defer step.deinit(); _=try step.own(value);
        const next=if(step.truthy(url)) blk: {
            const segment=try step.invoke(value,"replace",&.{regex,try step.text("")});
            const trailing=if(step.truthy(try step.invoke(url,"endsWith",&.{try step.text("/" )})))url else try step.concat(url,try step.text("/"));
            break :blk try step.concat(trailing,segment);
        } else value;
        const previous=url; url=c.JS_DupValue(s.engine.context,next); s.engine.freeValue(previous);
    }
    return s.own(c.JS_DupValue(s.engine.context,url));
}
pub fn moduleRegex(s:*Scope) !c.JSValue { return m.regex(s,"^\\.?/",""); }
