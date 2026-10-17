//! Prepared causal tests of the private mlly boundary; no substituted resolver,
//! builtin registry, successful filesystem operation or original JSON golden.
const std=@import("std");
const m=@import("extensions/native_mlly_values.zig");
const f=@import("extensions/native_mlly_function.zig");
const c=m.c;
const em=m.v.em;
fn install(engine:*em.Engine,name:[*:0]const u8,value:c.JSValue)!void{
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    try m.v.js.define(engine,global,name,c.JS_DupValue(engine.context,value));
}
fn directOOM(_: *em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{return error.OutOfMemory;}
fn captured(engine:*em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{return engine.checked(c.JS_Throw(engine.context,c.JS_DupValue(engine.context,roots[0])));}
fn pending(engine:*em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    const old=engine.captured_exception;engine.captured_exception=c.JS_DupValue(engine.context,roots[0]);if(old)|reason|engine.freeValue(reason);
    _=c.JS_Throw(engine.context,c.JS_DupValue(engine.context,roots[1]));return error.JavaScriptException;
}
fn pendingOOM(engine:*em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{_=c.JS_Throw(engine.context,c.JS_DupValue(engine.context,roots[0]));return error.OutOfMemory;}
fn fresh(engine:*em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{return engine.checked(engine.throwNativeOutOfMemory());}
fn nothing(_: *em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{return c.pi_js_undefined();}
fn receiverValue(engine:*em.Engine,receiver:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{return c.JS_DupValue(engine.context,receiver);}
fn rawTag(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue) callconv(.c)c.JSValue{return em.Engine.fromContext(context.?).throwNativeOutOfMemory();}
fn assertFatal(engine:*em.Engine)!void{
    const actual=engine.captured_exception orelse return error.MissingMllyFatal;
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    const caught=try m.v.js.get(engine,global,"mllyBoundaryCaught");defer engine.freeValue(caught);
    try std.testing.expectEqual(@as(c_int,0),c.JS_ToBool(engine.context,caught));
}
test "mlly local direct GPA error cannot enter a guest catch"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const function=try f.create(engine,"directOOM",0,directOOM,&.{});defer engine.freeValue(function);try install(engine,"MllyBoundaryProbe",function);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule("globalThis.mllyBoundaryCaught=false;try{MllyBoundaryProbe()}catch{globalThis.mllyBoundaryCaught=true}","mlly-direct-oom-boundary.mjs"));
    try assertFatal(engine);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,engine.native_allocation_exception orelse return error.MissingMllyNativeOOM));
}
test "mlly local pending completion wins over old capture and ordinary slot transfers"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const older=try m.v.js.object(engine);defer engine.freeValue(older);const newer=try m.v.js.object(engine);defer engine.freeValue(newer);
    const function=try f.create(engine,"pending",0,pending,&.{older,newer});defer engine.freeValue(function);try install(engine,"MllyBoundaryProbe",function);try install(engine,"MllyExpectedReason",newer);
    const result=try engine.evalModule("let caught;try{MllyBoundaryProbe()}catch(reason){caught=reason}if(caught!==MllyExpectedReason)throw Error('new pending identity');","mlly-pending-first.mjs");engine.freeValue(result);
    try std.testing.expect(engine.captured_exception==null);
}
test "mlly direct OOM preserves an existing pending Error identity"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const reason=try engine.checked(c.JS_NewError(engine.context));defer engine.freeValue(reason);
    const function=try f.create(engine,"pendingOOM",0,pendingOOM,&.{reason});defer engine.freeValue(function);try install(engine,"MllyBoundaryProbe",function);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule("globalThis.mllyBoundaryCaught=false;try{MllyBoundaryProbe()}catch{globalThis.mllyBoundaryCaught=true}","mlly-pending-error-oom.mjs"));try assertFatal(engine);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,reason,engine.captured_exception.?));
}
test "mlly captured ordinary reason transfers without a stale engine root"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const reason=try m.v.js.object(engine);defer engine.freeValue(reason);
    const function=try f.create(engine,"captured",0,captured,&.{reason});defer engine.freeValue(function);try install(engine,"MllyBoundaryProbe",function);try install(engine,"MllyExpectedReason",reason);
    const result=try engine.evalModule("let caught;try{MllyBoundaryProbe()}catch(reason){caught=reason}if(caught!==MllyExpectedReason)throw Error('ordinary reason identity');","mlly-ordinary-transfer.mjs");engine.freeValue(result);
    try std.testing.expect(engine.captured_exception==null);
}
test "mlly historical private allocation data remains ordinary in a later invocation"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    _=engine.throwNativeOutOfMemory();const reason=c.JS_GetException(engine.context);defer engine.freeValue(reason);try std.testing.expect(!c.JS_IsUncatchableError(reason));
    const function=try f.create(engine,"historical",0,captured,&.{reason});defer engine.freeValue(function);try install(engine,"MllyBoundaryProbe",function);try install(engine,"MllyExpectedReason",reason);
    const result=try engine.evalModule("let caught;try{MllyBoundaryProbe()}catch(reason){caught=reason}if(caught!==MllyExpectedReason)throw Error('historical reason was changed');","mlly-historical-data.mjs");engine.freeValue(result);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));try std.testing.expect(engine.captured_exception==null);
}
test "mlly fresh private allocation keeps its exact original fatal identity"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const function=try f.create(engine,"fresh",0,fresh,&.{});defer engine.freeValue(function);try install(engine,"MllyBoundaryProbe",function);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule("globalThis.mllyBoundaryCaught=false;try{MllyBoundaryProbe()}catch{globalThis.mllyBoundaryCaught=true}","mlly-fresh-identity.mjs"));try assertFatal(engine);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,engine.native_allocation_exception orelse return error.MissingMllyNativeOOM));
}
test "mlly constructor pre-body prototype failure crosses the same trusted exit"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const function=try f.create(engine,"construct",0,nothing,&.{});defer engine.freeValue(function);try install(engine,"MllyBoundaryProbe",function);try engine.bindFunction("MllyRawTaggedOOM",rawTag,0);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule(
        \\globalThis.mllyBoundaryCaught=false;const target=new Proxy(function(){},{get(target,key,receiver){if(key==='prototype')return MllyRawTaggedOOM();return Reflect.get(target,key,receiver)}});try{Reflect.construct(MllyBoundaryProbe,[],target)}catch{globalThis.mllyBoundaryCaught=true}
    ,"mlly-constructor-prebody.mjs"));try assertFatal(engine);
}
fn constructorAllocation(gpa:std.mem.Allocator)!void{
    const engine=try em.Engine.init(gpa,.{});defer engine.deinit();const generation=engine.native_allocation_generation;
    const function=f.create(engine,"construct",0,allocateBody,&.{}) catch |err| return engine.nativeAllocationError(err,generation);defer engine.freeValue(function);
    install(engine,"MllyBoundaryProbe",function) catch |err| return engine.nativeAllocationError(err,generation);
    const result=engine.evalModule("const value=new MllyBoundaryProbe();if(!(value instanceof MllyBoundaryProbe))throw Error('actual construction');","mlly-constructor-gpa.mjs") catch |err| return engine.nativeAllocationError(err,generation);engine.freeValue(result);c.JS_RunGC(engine.runtime);
}
fn allocateBody(engine:*em.Engine,_:c.JSValue,_:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{const bytes=try engine.gpa.alloc(u8,16);defer engine.gpa.free(bytes);return c.pi_js_undefined();}
test "mlly actual new and callable setup release every GPA failure reservation"{try std.testing.checkAllAllocationFailures(std.testing.allocator,constructorAllocation,.{});}
test "mlly local callable preserves ordinary arrow and method metadata receivers and construction"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();
    const ordinary=try f.create(engine,"ordinary",2,receiverValue,&.{});defer engine.freeValue(ordinary);try install(engine,"MllyOrdinary",ordinary);
    const arrow=try f.createArrow(engine,"",1,receiverValue,&.{});defer engine.freeValue(arrow);try install(engine,"MllyArrow",arrow);
    const method=try f.createMethod(engine,"value",0,receiverValue,&.{});defer engine.freeValue(method);try install(engine,"MllyMethod",method);
    const value=try engine.evalModule(
        \\const receiver={};if(MllyOrdinary.call(receiver)!==receiver||MllyMethod.call(receiver)!==receiver||MllyArrow.call(receiver)!==undefined)throw Error('actual receiver semantics');const made=new MllyOrdinary();if(!(made instanceof MllyOrdinary)||Object.getPrototypeOf(made)!==MllyOrdinary.prototype||MllyOrdinary.prototype.constructor!==MllyOrdinary)throw Error('ordinary construction');for(const [fn,name,length,prototype]of [[MllyOrdinary,'ordinary',2,true],[MllyArrow,'',1,false],[MllyMethod,'value',0,false]]){if(fn.name!==name||fn.length!==length||Object.hasOwn(fn,'prototype')!==prototype||Object.getPrototypeOf(fn)!==Function.prototype)throw Error('callable metadata');for(const property of ['name','length']){const d=Object.getOwnPropertyDescriptor(fn,property);if(d.enumerable||d.writable||!d.configurable)throw Error('descriptor')}}for(const fn of [MllyArrow,MllyMethod]){let rejected=false;try{new fn()}catch(reason){rejected=reason instanceof TypeError}if(!rejected)throw Error('nonconstructible callable')}
    ,"mlly-actual-callable-shapes.mjs");engine.freeValue(value);
}

fn closeHistorical(getter:bool)!void{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();const loop_generation=engine.native_allocation_generation;
    _=engine.throwNativeOutOfMemory();const historical=c.JS_GetException(engine.context);defer engine.freeValue(historical);try install(engine,"MllyHistoricalClose",historical);
    const iterable=try engine.eval(if(getter)"({[Symbol.iterator](){return this},next(){return{done:true}},get return(){throw MllyHistoricalClose}})" else "({[Symbol.iterator](){return this},next(){return{done:true}},return(){throw MllyHistoricalClose}})","mlly-historical-close.js",c.JS_EVAL_TYPE_GLOBAL);defer engine.freeValue(iterable);
    const symbol=try engine.checked(c.JS_GetIteratorSymbol(engine.context));defer engine.freeValue(symbol);var iterator=try m.v.js.Iterator.init(engine,iterable,symbol);defer iterator.deinit();
    const primary=try m.v.js.object(engine);defer engine.freeValue(primary);engine.captured_exception=c.JS_DupValue(engine.context,primary);
    const result=m.closeAbrupt(engine,&iterator,error.JavaScriptException,loop_generation);
    try std.testing.expect(result==error.JavaScriptException);try std.testing.expect(c.JS_IsStrictEqual(engine.context,primary,engine.captured_exception orelse return error.MissingMllyPrimary));
    try std.testing.expect(!c.JS_IsUncatchableError(historical));try std.testing.expect(iterator.closed);
}
test "mlly close getter does not promote older loop-born tagged data"{try closeHistorical(true);}
test "mlly close call does not promote older loop-born tagged data"{try closeHistorical(false);}
fn closeFresh(getter:bool)!void{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try engine.bindFunction("MllyRawTaggedOOM",rawTag,0);
    const iterable=try engine.eval(if(getter)"({[Symbol.iterator](){return this},next(){return{done:true}},get return(){return MllyRawTaggedOOM()}})" else "({[Symbol.iterator](){return this},next(){return{done:true}},return(){return MllyRawTaggedOOM()}})","mlly-fresh-close.js",c.JS_EVAL_TYPE_GLOBAL);defer engine.freeValue(iterable);
    const symbol=try engine.checked(c.JS_GetIteratorSymbol(engine.context));defer engine.freeValue(symbol);var iterator=try m.v.js.Iterator.init(engine,iterable,symbol);defer iterator.deinit();
    const primary=try m.v.js.object(engine);defer engine.freeValue(primary);engine.captured_exception=c.JS_DupValue(engine.context,primary);
    const result=m.closeAbrupt(engine,&iterator,error.JavaScriptException,engine.native_allocation_generation);
    try std.testing.expect(result==error.JavaScriptException);
    const reason=engine.captured_exception orelse return error.MissingMllyCloseFatal;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,reason,engine.native_allocation_exception orelse return error.MissingMllyNativeOOM));
}
test "mlly close getter fresh native allocation still overrides ordinary primary"{try closeFresh(true);}
test "mlly close call fresh native allocation still overrides ordinary primary"{try closeFresh(false);}

fn normalCloseBody(engine:*em.Engine,_:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{
    var s:m.Scope=.{.engine=engine};defer s.deinit();const generation=engine.native_allocation_generation;
    // The private-tagged ordinary data is born INSIDE this loop/callback. A
    // return getter/call rethrows it later; it is not a new native failure there.
    _=engine.throwNativeOutOfMemory();const historical=c.JS_GetException(engine.context);defer engine.freeValue(historical);try install(engine,"MllyNormalHistorical",historical);
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    const iterable=try s.call(try s.get(global,"MllyMakeNormalIterable"),c.pi_js_undefined(),args);
    const symbol=try s.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));var iterator=try m.v.js.Iterator.init(engine,iterable,symbol);defer iterator.deinit();
    const resolved=(try m.advance(engine,&iterator)) orelse return error.MissingMllyResolvedIteration;engine.freeValue(resolved);
    m.closeNormal(engine,&iterator) catch |err| {
        const closed=m.closeAbrupt(engine,&iterator,err,generation);
        if(args.len>1 and c.JS_ToBool(engine.context,args[1])!=0){_=try m.caught(&s,closed,generation);return engine.checked(engine.throwNativeOutOfMemory());}
        return m.exact(engine,closed,generation);
    };
    return c.pi_js_undefined();
}
fn forwardNormal(engine:*em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    const generation=engine.native_allocation_generation;
    return m.v.js.call(engine,roots[0],c.pi_js_undefined(),args) catch |err| return m.exact(engine,err,generation);
}
fn installNormal(engine:*em.Engine)!void{
    try engine.bindFunction("MllyRawTaggedOOM",rawTag,0);
    const setup=try engine.evalModule(
        \\globalThis.MllyMakeNormalIterable=kind=>({[Symbol.iterator](){return this},next(){return{done:false,value:'genuinely resolved'}},get return(){if(kind==='old-getter')throw MllyNormalHistorical;if(kind==='fresh-getter')return MllyRawTaggedOOM();return function(){if(kind==='old-call')throw MllyNormalHistorical;if(kind==='fresh-call')return MllyRawTaggedOOM();return 1}}});
    ,"mlly-normal-close-setup.mjs");engine.freeValue(setup);
    const inner=try f.create(engine,"normalInner",1,normalCloseBody,&.{});defer engine.freeValue(inner);try install(engine,"MllyNormalInner",inner);
    const outer=try f.create(engine,"normalOuter",1,forwardNormal,&.{inner});defer engine.freeValue(outer);try install(engine,"MllyNormalOuter",outer);
}
test "mlly successful break old return getter and call stay ordinary through nested full exits"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try installNormal(engine);
    const result=try engine.evalModule(
        \\for(const kind of ['old-getter','old-call']){let caught;try{MllyNormalOuter(kind)}catch(reason){caught=reason}if(caught!==MllyNormalHistorical)throw Error('normal close exact ordinary identity')}
    ,"mlly-normal-close-historical.mjs");engine.freeValue(result);try std.testing.expect(engine.captured_exception==null);
}
test "mlly successful break new return getter and call allocation stays fatal"{
    for([_] []const u8{"fresh-getter","fresh-call"})|kind|{
        const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try installNormal(engine);
        const source=try std.fmt.allocPrint(engine.gpa,"globalThis.mllyBoundaryCaught=false;try{{MllyNormalOuter('{s}')}}catch{{globalThis.mllyBoundaryCaught=true}}",.{kind});defer engine.gpa.free(source);
        try std.testing.expectError(error.JavaScriptException,engine.evalModule(source,"mlly-normal-close-fresh.mjs"));try assertFatal(engine);
    }
}
test "mlly later fresh allocation is not hidden by ordinary normal close provenance"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try installNormal(engine);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule("globalThis.mllyBoundaryCaught=false;try{MllyNormalOuter('old-call',true)}catch{globalThis.mllyBoundaryCaught=true}","mlly-after-normal-close-fresh.mjs"));try assertFatal(engine);
}
test "mlly normal break still rejects primitive return results"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try installNormal(engine);
    const result=try engine.evalModule("let caught;try{MllyNormalOuter('primitive')}catch(reason){caught=reason}if(!(caught instanceof TypeError))throw Error('normal return validation');","mlly-normal-close-primitive.mjs");engine.freeValue(result);try std.testing.expect(engine.captured_exception==null);
}
fn parentFatal(engine:*em.Engine,_:c.JSValue,_:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    const generation=engine.native_allocation_generation;
    if(engine.checked(engine.throwNativeOutOfMemory()))|unexpected|{engine.freeValue(unexpected);return error.ExpectedMllyParentFatal;}else|err|{try std.testing.expect(m.exact(engine,err,generation)==error.JavaScriptException);}
    const primary=engine.captured_exception orelse return error.MissingMllyParentFatal;engine.captured_exception=null;defer engine.freeValue(primary);
    try install(engine,"MllyParentFatalReason",primary);
    // Entered cleanup may catch an ordinary child close. The already trusted
    // parent fatal keeps its flag/identity even though child provenance advances.
    const called=m.v.js.call(engine,roots[0],c.pi_js_undefined(),&.{}) catch |err| return err;engine.freeValue(called);
    return engine.checked(c.JS_Throw(engine.context,c.JS_DupValue(engine.context,primary)));
}
test "mlly nested ordinary close cannot consume an already trusted retained parent fatal"{
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try installNormal(engine);
    const cleanup=try engine.eval("(()=>{try{MllyNormalInner('old-call')}catch(reason){if(reason!==MllyNormalHistorical)throw reason}})","mlly-parent-fatal-cleanup.js",c.JS_EVAL_TYPE_GLOBAL);defer engine.freeValue(cleanup);
    const function=try f.create(engine,"retainedParentFatal",0,parentFatal,&.{cleanup});defer engine.freeValue(function);try install(engine,"MllyRetainedParentFatal",function);
    try std.testing.expectError(error.JavaScriptException,engine.evalModule("globalThis.mllyBoundaryCaught=false;try{MllyRetainedParentFatal()}catch{globalThis.mllyBoundaryCaught=true}","mlly-parent-fatal-retained.mjs"));try assertFatal(engine);
    const global=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);const expected=try m.v.js.get(engine,global,"MllyParentFatalReason");defer engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,expected));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,engine.native_allocation_exception.?));
}

const module_resolve=@import("extensions/native_mlly_module_resolve.zig");
const format=@import("extensions/native_mlly_format.zig");
fn formatCall(engine:*em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    var s:m.Scope=.{.engine=engine};defer s.deinit();
    const context:m.Context=.{.engine=engine,.owner=roots[0]};
    return c.JS_DupValue(engine.context,try format.defaultGetFormatWithoutErrors(context,&s,if(args.len>0)args[0] else c.pi_js_undefined(),if(args.len>1)args[1] else c.pi_js_undefined()));
}
/// Complete actual imports are required. These real URL instances exercise
/// protocol-before-pathname, all actual handlers and unknown->null dispatch.
pub fn verifyActualFormatDispatch(engine:*em.Engine,actual:m.Imports)!void{
    const owner=try m.initialize(engine,actual);defer engine.freeValue(owner);
    const function=try f.create(engine,"defaultGetFormatWithoutErrors",2,formatCall,&.{owner});defer engine.freeValue(function);try install(engine,"ActualMllyFormatProbe",function);
    const result=try engine.evalModule(
        \\for(const [address,expected,path]of [['file:///C:/owned/a.mjs','module',true],['node:fs','builtin',false],['http://example.invalid/a',null,false],['https://example.invalid/a',null,false],['data:text/javascript,export%20default%201','module',true],['data:application/json,%7B%7D','json',true],['custom:owned',null,false]]){const url=new URL(address),protocol=url.protocol,pathname=url.pathname,log=[];Object.defineProperty(url,'protocol',{get(){log.push('protocol');return protocol}});Object.defineProperty(url,'pathname',{get(){log.push('pathname');return pathname}});const value=ActualMllyFormatProbe(url,{parentURL:'file:///C:/owned/base.mjs'});if(value!==expected||log.join(',')!==(path?'protocol,pathname':'protocol'))throw Error(JSON.stringify({address,value,log}))}
    ,"mlly-actual-format-dispatch.mjs");engine.freeValue(result);
}
/// Actual URL/FS imports remain required; this entry checks only the causal
/// old-numeric getter trace, without prescribing a package/FS answer.
pub fn verifyActualPostdecrementNumeric(engine:*em.Engine,actual:m.Imports)!void{
    const owner=try m.initialize(engine,actual);defer engine.freeValue(owner);
    const function=try f.create(engine,"defaultGetFormatWithoutErrors",2,formatCall,&.{owner});defer engine.freeValue(function);try install(engine,"ActualMllyNumericProbe",function);
    const result=try engine.evalModule(
        \\for(const kind of ['string-zero','object-zero','nan','bigint-zero','tiny-nonzero']){const log=[];const length=kind==='string-zero'?'0':kind==='object-zero'?{[Symbol.toPrimitive](hint){log.push(['numeric',hint]);return 0}}:kind==='nan'?NaN:kind==='bigint-zero'?0n:Number.MIN_VALUE;const pathname={length,codePointAt(index){log.push(['codePointAt',String(index)]);return 47},slice(index){log.push(['slice',String(index)]);return '.mjs'}};const url=new URL('file:///C:/owned/nonexistent.mjs');Object.defineProperty(url,'pathname',{get(){return pathname}});ActualMllyNumericProbe(url,{});const numeric=log.filter(row=>row[0]==='numeric'),points=log.filter(row=>row[0]==='codePointAt');if(numeric.length!==(kind==='object-zero'?1:0)||(numeric.length&&numeric[0][1]!=='number')||points.length!==(kind==='tiny-nonzero'?1:0))throw Error(JSON.stringify({kind,log}))}
    ,"mlly-postdecrement-numeric.mjs");engine.freeValue(result);
}
/// Two profiles per public URL export: ordinary older-loop reason, or a new
/// actual native allocation after that ordinary boundary. Real Node bindings
/// are mandatory; a live String.replace hook causes the nested source entry.
pub fn verifyActualURLWrapperReentry(engine:*em.Engine,actual:m.Imports,name:[]const u8,later_fresh:bool)!void{
    if(!std.mem.eql(u8,name,"fileURLToPath") and !std.mem.eql(u8,name,"pathToFileURL"))return error.InvalidMllyURLControlName;
    try installNormal(engine);
    const namespace=try @import("extensions/native_mlly_urls.zig").create(engine,.{.file_url_to_path=actual.file_url_to_path,.path_to_file_url=actual.path_to_file_url});defer engine.freeValue(namespace);try install(engine,"ActualMllyURLs",namespace);
    const source=try std.fmt.allocPrint(engine.gpa,
        "const descriptor=Object.getOwnPropertyDescriptor(String.prototype,'replace');Object.defineProperty(String.prototype,'replace',{{configurable:true,value:function(){{return MllyNormalInner('old-call',{s})}}}});globalThis.mllyBoundaryCaught=false;let caught;try{{ActualMllyURLs.{s}('owned/path')}}catch(reason){{globalThis.mllyBoundaryCaught=true;caught=reason}};if(caught!==MllyNormalHistorical)throw Error('public URL ordinary reentry identity');Object.defineProperty(String.prototype,'replace',descriptor)",
        .{if(later_fresh)"true" else "false",name});defer engine.gpa.free(source);
    if(later_fresh){try std.testing.expectError(error.JavaScriptException,engine.evalModule(source,"mlly-url-reentry-later-fresh.mjs"));try assertFatal(engine);try std.testing.expect(c.JS_IsStrictEqual(engine.context,engine.captured_exception.?,engine.native_allocation_exception orelse return error.MissingMllyURLFreshReason));}else{const value=try engine.evalModule(source,"mlly-url-reentry-ordinary.mjs");engine.freeValue(value);try std.testing.expect(engine.captured_exception==null);}
}
fn failedRealFile(engine:*em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    const path=try m.v.js.call(engine,roots[0],c.pi_js_undefined(),args);engine.freeValue(path);
    return engine.checked(c.JS_Throw(engine.context,c.JS_DupValue(engine.context,roots[1])));
}
/// Controlled ordinary failure AFTER a real actual Node URL conversion, not a
/// successful filesystem/path substitute. Realm teardown owns any failed probe.
pub fn verifyActualDescriptorOrder(engine:*em.Engine,actual:m.Imports)!void{
    engine.native_exception_diagnostics_suppressed+=1;defer engine.native_exception_diagnostics_suppressed-=1;
    var s:m.Scope=.{.engine=engine};defer s.deinit();const marker=try s.object();
    const fault=try s.own(try f.create(engine,"controlledFileURLFailure",1,failedRealFile,&.{actual.file_url_to_path,marker}));
    var changed=actual;changed.file_url_to_path=fault;const owner=try s.own(try m.initialize(engine,changed));
    const setup=try s.own(try engine.evalModule(
        \\const define=Object.defineProperty,dd=Object.getOwnPropertyDescriptor(Object,'defineProperty'),sd=Object.getOwnPropertyDescriptor(globalThis,'String'),string=String,log=[];export const url=new URL('file:///C:/owned/missing.mjs'),base=new URL('file:///C:/owned/base.mjs');
        \\export function arm(){define(Object,'defineProperty',{configurable:true,get(){log.push('get defineProperty');return function(...args){log.push('call defineProperty');return Reflect.apply(define,this,args)}}});define(globalThis,'String',{configurable:true,writable:true,value:function(...args){log.push('call String');return Reflect.apply(string,undefined,args)}})}
        \\export function verify(){if(log.join(',')!=='get defineProperty,call String,call defineProperty,get defineProperty,call String,call defineProperty')throw Error(JSON.stringify(log))};export function restore(){define(Object,'defineProperty',dd);define(globalThis,'String',sd)}
    ,"mlly-finalize-descriptor-order-setup.mjs"));
    const armed=try m.v.js.invoke(engine,setup,"arm",&.{});engine.freeValue(armed);
    var resolver:module_resolve.Resolver=.{.context=.{.engine=engine,.owner=owner}};
    if(resolver.finalize(&s,try s.get(setup,"url"),try s.get(setup,"base"),false))|unexpected|{_=unexpected;return error.ExpectedControlledFileURLFailure;} else |err| {
        if(err!=error.JavaScriptException)return err;
        const reason=engine.captured_exception orelse return error.MissingControlledFileURLReason;engine.captured_exception=null;defer engine.freeValue(reason);
        if(c.JS_IsUncatchableError(reason))return m.throwReason(engine,reason);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context,reason,marker));
    }
    const verified=try m.v.js.invoke(engine,setup,"verify",&.{});engine.freeValue(verified);
    // Successful probe only. Any prior ordinary/fatal/OOM exits to fresh realm
    // teardown without a guest restoration hook that could replace its cause.
    const restored=try m.v.js.invoke(engine,setup,"restore",&.{});engine.freeValue(restored);
}
