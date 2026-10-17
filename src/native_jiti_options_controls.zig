//! Prepared real realm options controls. No factory/context/cache is invented.
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const options = @import("extensions/native_jiti_options.zig");
fn install(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try v.js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn subject(engine: *v.em.Engine) !void {
    const function = try options.create(engine); defer engine.freeValue(function);
    try install(engine, "ActualJitiOptions", function);
}
pub fn verifyDefaultsOverridesAndCallable(engine: *v.em.Engine) !void {
    try subject(engine);
    const result = try engine.evalModule(
        \\const env=Object.getOwnPropertyDescriptor(process,'env'),bun=Object.getOwnPropertyDescriptor(globalThis,'Bun');
        \\try{Object.defineProperty(process,'env',{configurable:true,writable:true,value:{}});delete globalThis.Bun;
        \\const fn=ActualJitiOptions,opts=fn({});if(fn.name!=='resolveJitiOptions'||fn.length!==1||!Object.hasOwn(fn,'prototype'))throw Error('ordinary Source declaration');
        \\if(Object.keys(opts).join()!=='fsCache,rebuildFsCache,moduleCache,debug,sourceMaps,interopDefault,extensions,alias,nativeModules,transformModules,tryNative,esmEvalTempFile,jsx,tsconfigPaths')throw Error('default key order');
        \\if(opts.fsCache!==true||opts.moduleCache!==true||opts.interopDefault!==true||opts.tryNative!==false||opts.jsx!==false||opts.tsconfigPaths!==false)throw Error('default values');
        \\if(opts.extensions.join()!=='.js,.mjs,.cjs,.ts,.tsx,.mts,.cts,.mtsx,.ctsx')throw Error('extensions');
        \\const overridden=fn({cache:false,requireCache:false,fsCache:'explicit',moduleCache:'explicit-module'});if(overridden.fsCache!=='explicit'||overridden.moduleCache!=='explicit-module')throw Error('override precedence');
        \\const constructed=new fn({debug:true});if(constructed.debug!==true||constructed instanceof fn)throw Error('ordinary function object return');
        \\process.env={JITI_CACHE:'false',JITI_FS_CACHE:'true',JITI_REQUIRE_CACHE:'false',JITI_JSX:'true',JITI_TSCONFIG_PATHS:'config-path'};
        \\const parsed=fn({});if(parsed.fsCache!==true||parsed.moduleCache!==false||parsed.tsconfigPaths!=='config-path'||parsed.extensions.slice(-2).join()!=='.jsx,.tsx'||parsed.extensions.filter(x=>x==='.tsx').length!==2)throw Error('env fallback/raw/jsx');
        \\}finally{Object.defineProperty(process,'env',env);if(bun)Object.defineProperty(globalThis,'Bun',bun);else delete globalThis.Bun}export const passed=true;
    , "jiti-options-defaults-overrides-callable.mjs");
    defer engine.freeValue(result);
}
pub fn verifyInheritedSettersAndSymbols(engine: *v.em.Engine) !void {
    try subject(engine);
    const result = try engine.evalModule(
        \\const env=Object.getOwnPropertyDescriptor(process,'env'),old=Object.getOwnPropertyDescriptor(Object.prototype,'fsCache'),key=Symbol('options'),identity={};let calls=0;
        \\try{Object.defineProperty(process,'env',{configurable:true,writable:true,value:{}});Object.defineProperty(Object.prototype,'fsCache',{configurable:true,set(value){calls++}});
        \\const user={cache:false,[key]:identity},actual=ActualJitiOptions(user);if(calls!==1||actual.fsCache!==true||actual[key]!==identity||!Object.hasOwn(actual,'fsCache'))throw Error('Source assignment/spread versus literal define');
        \\}finally{Object.defineProperty(process,'env',env);if(old)Object.defineProperty(Object.prototype,'fsCache',old);else delete Object.prototype.fsCache}export const passed=true;
    , "jiti-options-inherited-setters-symbols.mjs");
    defer engine.freeValue(result);
}
/// The accepted trace must come from the pinned original options.ts, loaded
/// by the genuine jiti reference package. This helper never creates an oracle.
pub fn verifyAcceptedGetterAndCatchTrace(engine: *v.em.Engine, accepted_source_trace: c.JSValue) !void {
    try subject(engine); try install(engine, "AcceptedJitiOptionsTrace", accepted_source_trace);
    const result = try engine.evalModule(
        \\const env=Object.getOwnPropertyDescriptor(process,'env'),parse=Object.getOwnPropertyDescriptor(JSON,'parse'),boolean=Object.getOwnPropertyDescriptor(globalThis,'Boolean'),trace=[],marker={get toString(){throw Error('caught reason formatted')}};
        \\const originalParse=JSON.parse,originalBoolean=Boolean,target={JITI_CACHE:'false',JITI_TSCONFIG_PATHS:'bad'},view=new Proxy(target,{get(t,k,r){trace.push(['get',String(k)]);return Reflect.get(t,k,r)},has(t,k){trace.push(['has',String(k)]);return Reflect.has(t,k)}});
        \\try{Object.defineProperty(process,'env',{configurable:true,get(){trace.push(['env']);return view}});Object.defineProperty(JSON,'parse',{configurable:true,writable:true,value:function(value){'use strict';trace.push(['parse',this===JSON,value]);if(value==='bad')throw marker;return originalParse(value)}});
        \\Object.defineProperty(globalThis,'Boolean',{configurable:true,writable:true,value:function(value){'use strict';trace.push(['Boolean',this===undefined,value]);return originalBoolean(value)}});
        \\let reads=0;const user={get cache(){trace.push(['cache',++reads]);return false},get requireCache(){trace.push(['requireCache']);return undefined}},actual=ActualJitiOptions(user);trace.push(['result',actual.fsCache,actual.tsconfigPaths]);
        \\}finally{Object.defineProperty(process,'env',env);Object.defineProperty(JSON,'parse',parse);Object.defineProperty(globalThis,'Boolean',boolean)}
        \\if(JSON.stringify(trace)!==JSON.stringify(AcceptedJitiOptionsTrace))throw Error('actual options getter/catch Source trace');export const passed=true;
    , "jiti-options-accepted-getter-catch-trace.mjs");
    defer engine.freeValue(result);
}
