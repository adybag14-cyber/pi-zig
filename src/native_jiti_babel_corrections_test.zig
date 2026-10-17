//! Prepared causal checks, not a default Jiti bootstrap or Babel golden.
const std=@import("std");
const v=@import("extensions/native_ai_provider_values.zig");
const c=v.c;
const generator=@import("extensions/native_jiti_babel_generator.zig");
const plugins=@import("extensions/native_jiti_babel_plugins.zig");
fn equivalent(source:[]const u8)!void{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const formatted=try generator.pretty(engine.gpa,source);defer engine.gpa.free(formatted);
    // Both executions use the actual VM. No manually authored return-value
    // oracle or Source/Babel function text is substituted into either side.
    const original=try engine.eval(source,"babel-correction-original.js",c.JS_EVAL_TYPE_GLOBAL);defer engine.freeValue(original);
    const generated=try engine.eval(formatted,"babel-correction-generated.js",c.JS_EVAL_TYPE_GLOBAL);defer engine.freeValue(generated);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,original,generated));
}
test "native Babel correction printer preserves LS PS return async and update restrictions"{
    inline for(.{"\xE2\x80\xA8","\xE2\x80\xA9"})|line|{
        try equivalent("(function(){function f(){return"++line++"owned;}return f()})()");
        try equivalent("(function(){let async=7;async"++line++"function f(){return 1}return f()})()");
        try equivalent("(function(){let value=1;value"++line++"++value;return value})()");
    }
}
test "native Babel correction printer preserves numeric member and regex word boundaries"{
    try equivalent("(1 .toString())");
    try equivalent("(/x/ instanceof RegExp)");
}
fn actualBackend(engine:*v.em.Engine)!c.JSValue{
    try @import("extensions/node_url.zig").install(engine);
    const node=engine.native_module_values.get("node:url").?;
    const file=try v.js.get(engine,node,"fileURLToPath");defer engine.freeValue(file);
    const path=try v.js.get(engine,node,"pathToFileURL");defer engine.freeValue(path);
    const urls=try @import("extensions/native_mlly_urls.zig").create(engine,.{.file_url_to_path=file,.path_to_file_url=path});defer engine.freeValue(urls);
    const paths=try @import("extensions/native_pathe.zig").create(engine);defer engine.freeValue(paths);
    const dirname=try v.js.get(engine,paths,"dirname");defer engine.freeValue(dirname);
    const mlly_file=try v.js.get(engine,urls,"fileURLToPath");defer engine.freeValue(mlly_file);
    const mlly_path=try v.js.get(engine,urls,"pathToFileURL");defer engine.freeValue(mlly_path);
    return @import("extensions/native_jiti_default_transform.zig").create(engine,.{.file_url_to_path=mlly_file,.path_to_file_url=mlly_path,.dirname=dirname});
}
fn install(s:*v.Scope)!void{
    const backend=try s.own(try actualBackend(s.engine));const global=try s.own(try s.engine.checked(c.JS_GetGlobalObject(s.engine.context)));
    try s.put(global,"ActualCorrectedBabel",backend);
}
fn eval(s:*v.Scope,source:[]const u8)!void{_ = try s.own(try s.engine.evalModule(source,"babel-plugin-correction.mjs"));}
const options="{source:'export const value=1;',ts:true,interopDefault:true,babel}";
test "native Babel correction refuses actual nonempty arrays and nonenumerable indices"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();try install(&s);
    try eval(&s,"let executed=0;const plugin=()=>{executed++;return{}};for(const list of [[plugin],Object.defineProperty([],'0',{value:plugin,enumerable:false})]){const babel={plugins:list};let reason;try{ActualCorrectedBabel("++options++")}catch(error){reason=error}if(reason?.code!=='PI_UNSUPPORTED_JITI_DEFAULT_TRANSFORM')throw Error('nonempty plugin was silently admitted')}if(executed!==0)throw Error('unsupported plugin was executed');");
    try std.testing.expect(engine.captured_exception==null);
}
test "native Babel correction empty array custom iterator is consumed through actual done"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();try install(&s);
    try eval(&s,"let steps=0,values=0,closes=0;const list=[];list[Symbol.iterator]=function(){if(this!==list)throw Error('iterator receiver');return{next(){steps++;return steps===1?{get done(){return false},get value(){values++;return ()=>({})}}:{done:true}},get return(){closes++;return()=>({})}}};const babel={plugins:list};let reason;try{ActualCorrectedBabel("++options++")}catch(error){reason=error}if(reason?.code!=='PI_UNSUPPORTED_JITI_DEFAULT_TRANSFORM'||steps!==2||values!==1||closes!==0)throw Error('actual iterator/full consumption/close policy');");
    try eval(&s,"let emptySteps=0;const list=[];list[Symbol.iterator]=()=>({next(){emptySteps++;return{done:true,get value(){throw Error('must not read done value')}}},get return(){throw Error('must not close completed spread')}});const babel={plugins:list};const result=ActualCorrectedBabel("++options++");if(typeof result.code!=='string'||emptySteps!==1)throw Error('empty custom iterator was not consumed');");
}
test "native Babel correction rereads plugins after isArray before spread"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();try install(&s);
    try eval(&s,"const log=[],first=[],second={*[Symbol.iterator](){log.push('iterator');yield ()=>({});log.push('done')}};let reads=0;const babel={};Object.defineProperty(babel,'plugins',{get(){log.push('get'+(++reads));return reads===1?first:second}});const original=Array.isArray;Array.isArray=function(value){if(this!==Array||value!==first)throw Error('isArray receiver/argument');log.push('isArray');return original(value)};let reason;try{ActualCorrectedBabel("++options++")}catch(error){reason=error}Array.isArray=original;if(reason?.code!=='PI_UNSUPPORTED_JITI_DEFAULT_TRANSFORM'||log.join(',')!=='get1,isArray,get2,iterator,done')throw Error('live reread/order');");
    try eval(&s,"const reason={secondGetter:true};let reads=0;const first=[];Object.defineProperty(first,Symbol.iterator,{get(){throw Error('first array must not be consumed')}});const babel={};Object.defineProperty(babel,'plugins',{get(){if(++reads===1)return first;throw reason}});let caught;try{ActualCorrectedBabel("++options++")}catch(error){caught=error}if(caught!==reason||reads!==2)throw Error('second getter throw lost');");
}
test "native Babel correction abrupt iterator steps preserve raw reason without close"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();try install(&s);
    try eval(&s,"for(const mode of ['next-getter','next-call','done','value','later-next']){const reason={mode},list=[];let closes=0,steps=0;list[Symbol.iterator]=()=>({get next(){if(mode==='next-getter')throw reason;return function(){if(mode==='later-next'&&++steps===1)return{done:false,value:()=>({})};if(mode==='next-call'||mode==='later-next')throw reason;return{get done(){if(mode==='done')throw reason;return false},get value(){throw reason}}}},get return(){closes++;return()=>({})}});const babel={plugins:list};let caught;try{ActualCorrectedBabel("++options++")}catch(error){caught=error}if(caught!==reason||closes!==0)throw Error('abrupt Step close/identity')}");
    try std.testing.expect(engine.captured_exception==null);
}
fn pending(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
    const engine=v.em.Engine.fromContext(context.?);const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    const value=c.JS_GetPropertyStr(engine.context,global,"PendingPluginValue");
    if(c.JS_IsException(value))return value;
    const fresh=c.JS_GetPropertyStr(engine.context,global,"PendingPluginFresh");defer engine.freeValue(fresh);
    if(c.JS_ToBool(engine.context,fresh)==1){_ = engine.throwNativeOutOfMemory();}
    else{const reason=c.JS_GetPropertyStr(engine.context,global,"PendingPluginReason");if(c.JS_IsException(reason)){engine.freeValue(value);return reason;}_ = c.JS_Throw(engine.context,reason);}
    return value;
}
test "native Babel correction iterator pending events stop downstream calls and publication"{
    for([_]bool{false,true})|fresh|for([_][]const u8{"iterator-getter","iterator-call","next-getter","next-call","done","value"})|phase|{
        const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();
        defer if(engine.captured_exception)|reason|c.JS_ClearUncatchableError(engine.context,reason);
        try engine.bindFunction("PendingPluginEvent",pending,0);
        const setup=try std.fmt.allocPrint(engine.gpa,"globalThis.PendingPluginFresh={s};globalThis.PendingPluginCoercions=0;globalThis.PendingPluginReason={{toString(){{PendingPluginCoercions++;throw Error('must not coerce')}}}};globalThis.PendingPluginLog=[];const phase='{s}',list=[];const result={{get done(){{PendingPluginLog.push('done');if(phase==='done'){{globalThis.PendingPluginValue=false;return PendingPluginEvent()}}return false}},get value(){{PendingPluginLog.push('value');globalThis.PendingPluginValue=()=>({{}});return PendingPluginEvent()}}}};const next=function(){{PendingPluginLog.push('next');if(phase==='next-call'){{globalThis.PendingPluginValue=result;return PendingPluginEvent()}}return result}};const iterator={{get next(){{PendingPluginLog.push('get next');if(phase==='next-getter'){{globalThis.PendingPluginValue=next;return PendingPluginEvent()}}return next}}}};const method=function(){{PendingPluginLog.push('iterator');if(phase==='iterator-call'){{globalThis.PendingPluginValue=iterator;return PendingPluginEvent()}}return iterator}};Object.defineProperty(list,Symbol.iterator,{{get(){{PendingPluginLog.push('get iterator');if(phase==='iterator-getter'){{globalThis.PendingPluginValue=method;return PendingPluginEvent()}}return method}}}});globalThis.PendingPluginOptions={{babel:{{plugins:list}}}};",.{if(fresh)"true" else "false",phase});defer engine.gpa.free(setup);
        const result=try engine.eval(setup,"babel-pending-plugin-setup.js",c.JS_EVAL_TYPE_GLOBAL);engine.freeValue(result);
        const options_value=try s.global("PendingPluginOptions");const generation=engine.native_allocation_generation;
        try std.testing.expectError(error.JavaScriptException,plugins.nonempty(engine,options_value));
        const reason=engine.captured_exception orelse return error.MissingPendingPluginReason;
        if(fresh){try std.testing.expect(c.JS_IsStrictEqual(engine.context,reason,engine.native_allocation_exception.?));try std.testing.expect(c.JS_IsUncatchableError(reason));try std.testing.expectEqual(generation+%1,engine.native_allocation_generation);}
        else try std.testing.expect(c.JS_IsStrictEqual(engine.context,reason,try s.global("PendingPluginReason")));
        const log=try s.global("PendingPluginLog");const actual=try engine.stringify(log);defer engine.gpa.free(actual);
        const expected=if(std.mem.eql(u8,phase,"iterator-getter"))"[\"get iterator\"]" else if(std.mem.eql(u8,phase,"iterator-call"))"[\"get iterator\",\"iterator\"]" else if(std.mem.eql(u8,phase,"next-getter"))"[\"get iterator\",\"iterator\",\"get next\"]" else if(std.mem.eql(u8,phase,"next-call"))"[\"get iterator\",\"iterator\",\"get next\",\"next\"]" else if(std.mem.eql(u8,phase,"done"))"[\"get iterator\",\"iterator\",\"get next\",\"next\",\"done\"]" else "[\"get iterator\",\"iterator\",\"get next\",\"next\",\"done\",\"value\"]";
        try std.testing.expectEqualStrings(expected,actual);try std.testing.expect(c.JS_IsStrictEqual(engine.context,try s.global("PendingPluginCoercions"),c.JS_NewInt32(engine.context,0)));try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
    };
}
const Quota=struct{
    var steps:usize=0;
    fn iterator(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
        const root=c.JS_GetGlobalObject(context);defer c.JS_FreeValue(context,root);return c.JS_GetPropertyStr(context,root,"QuotaPluginIterator");
    }
    fn next(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
        steps+=1;const root=c.JS_GetGlobalObject(context);defer c.JS_FreeValue(context,root);return c.JS_GetPropertyStr(context,root,"QuotaPluginStep");
    }
};
test "native Babel correction native iterator budget is fatal while guest lookalike is ordinary"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();
    defer if(engine.captured_exception)|reason|c.JS_ClearUncatchableError(engine.context,reason);
    try engine.bindFunction("QuotaPluginMakeIterator",Quota.iterator,0);try engine.bindFunction("QuotaPluginNext",Quota.next,0);
    const setup=try engine.eval("globalThis.QuotaPluginStep={done:false,value:0};globalThis.QuotaPluginIterator={next:QuotaPluginNext};const list=[];list[Symbol.iterator]=QuotaPluginMakeIterator;globalThis.QuotaPluginOptions={babel:{plugins:list}};","babel-plugin-quota-setup.js",c.JS_EVAL_TYPE_GLOBAL);engine.freeValue(setup);
    const opts=try s.global("QuotaPluginOptions");const saved=engine.options.interrupt_budget;defer engine.options.interrupt_budget=saved;const interrupts=engine.interrupts;defer engine.interrupts=interrupts;
    engine.options.interrupt_budget=0;engine.interrupts=0;Quota.steps=0;
    try std.testing.expectError(error.JavaScriptException,plugins.nonempty(engine,opts));
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));try std.testing.expectEqual(@as(usize,255),Quota.steps);
    const other=try v.em.Engine.init(std.testing.allocator,.{});defer other.deinit();var t:v.Scope=.{.engine=other};defer t.deinit();try install(&t);
    try eval(&t,"const reason=Error('interrupted');reason.name='InternalError';const list=[];list[Symbol.iterator]=()=>({next(){throw reason}});const babel={plugins:list};let caught;try{ActualCorrectedBabel("++options++")}catch(error){caught=error}if(caught!==reason)throw Error('guest lookalike promoted');");
    try std.testing.expect(other.captured_exception==null);
}
fn collectPluginTemporaries(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
    const engine=v.em.Engine.fromContext(context.?);
    c.JS_ClearKeptObjects(engine.runtime);c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
test "native Babel correction plugin temporaries retire while iterator record and arguments remain rooted"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    try engine.bindFunction("CollectPluginTemporaries",collectPluginTemporaries,0);
    // WeakRefs are created in the completed setup job, before the actual used
    // boundary is called. The fixture pool releases each target when Source
    // returns it; later callbacks collect and check the resulting native roots.
    const setup=try engine.evalModule(
        \\const pool=Object.create(null),weak=Object.create(null),arrayDescriptor=Object.getOwnPropertyDescriptor(globalThis,'Array');let reads=0,steps=0,checks=0;
        \\function take(name){const result=pool[name];delete pool[name];return result}
        \\function check(dead=[],live=[]){CollectPluginTemporaries();for(const name of dead)if(weak[name].deref()!==undefined)throw Error('retained '+name);for(const name of live)if(weak[name].deref()===undefined)throw Error('released '+name);checks++}
        \\pool.truth={};pool.firstPlugins=[];
        \\pool.firstReceiver={get plugins(){return take('firstPlugins')}};
        \\pool.isArray=function(value){check(['firstReceiver'],['array','isArray','firstPlugins']);if(value!==weak.firstPlugins.deref())throw Error('condition argument');return true};
        \\pool.array={get isArray(){return take('isArray')}};
        \\pool.secondReceiver={get plugins(){return take('iterable')}};
        \\pool.iterable={get [Symbol.iterator](){check(['secondReceiver']);return take('method')}};
        \\pool.method=function(){check([],['iterable','method']);return take('iterator')};
        \\pool.iterator={get next(){check(['iterable','method'],['iterator']);return take('next')}};
        \\pool.next=function(){check([],['iterator','next']);if(++steps===1)return take('step');check(['step'],['value']);return take('last')};
        \\pool.step={get done(){return false},get value(){check([],['step']);return take('value')}};pool.value={};
        \\pool.last={get done(){return take('done')},get value(){throw Error('completed value getter')}};pool.done={};
        \\for(const name of Object.keys(pool))weak[name]=new WeakRef(pool[name]);
        \\Object.defineProperty(globalThis,'Array',{configurable:true,get(){check(['truth']);return take('array')}});
        \\globalThis.RetirementPluginOptions={get babel(){if(++reads===1)return take('truth');if(reads===2)return take('firstReceiver');check(['array','isArray','firstPlugins']);return take('secondReceiver')}};
        \\export function verify(){check(Object.keys(weak));if(reads!==3||steps!==2||checks!==11)throw Error('retirement checkpoints');Object.defineProperty(globalThis,'Array',arrayDescriptor)}
    ,"babel-plugin-retirement-setup.mjs");defer engine.freeValue(setup);
    c.JS_ClearKeptObjects(engine.runtime);
    const global=try engine.checked(c.JS_GetGlobalObject(engine.context));defer engine.freeValue(global);
    const opts=try v.js.get(engine,global,"RetirementPluginOptions");defer engine.freeValue(opts);
    try std.testing.expect(try plugins.nonempty(engine,opts));
    const verified=try v.js.invoke(engine,setup,"verify",&.{});defer engine.freeValue(verified);
    try std.testing.expect(engine.captured_exception==null);
    try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
}
