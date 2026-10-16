// Genuine Source uses node:util.types.isAsyncFunction. Native uses the VM's
// actual JS_IsAsyncFunction. Prototype tags alone must fail the negative control.
const classes=globalThis.ActualSdkAsyncClasses;
const isAsync=globalThis.ActualSdkIsAsyncFunction;
if(typeof isAsync!=='function')throw Error('Actual runtime async-brand primitive required');
const rows=[];const add=(name,value)=>rows.push({name,value});
const metadata=fn=>({name:fn.name,length:fn.length,async:isAsync(fn),ownPrototype:Object.hasOwn(fn,'prototype')});
const asyncPrototype=Object.getPrototypeOf(async()=>{});
const ordinary=function ordinary(){};Object.setPrototypeOf(ordinary,asyncPrototype);
add('prototype-tag-negative-control',{tag:Object.prototype.toString.call(ordinary),async:isAsync(ordinary)});
for(const name of ['ModelRuntime','ModelConfig','InMemoryCodingAgentModelsStore','FileModelsStore','AgentSessionRuntime']){
  const ctor=classes[name];if(typeof ctor!=='function')throw Error('Missing actual class '+name);
  const members=Object.getOwnPropertyNames(ctor.prototype).map(name=>{
    const descriptor=Object.getOwnPropertyDescriptor(ctor.prototype,name);
    return {name,enumerable:descriptor.enumerable,kind:descriptor.get?'get':'value',function:metadata(descriptor.get??descriptor.value)};
  });
  add('actual-class-brand-'+name,{constructor:metadata(ctor),members});
}
add('actual-static-brand-ModelRuntime-create',metadata(classes.ModelRuntime.create));
add('actual-static-brand-ModelConfig-load',metadata(classes.ModelConfig.load));
const memory=new classes.InMemoryCodingAgentModelsStore();
const trace=[];const savedClone=globalThis.structuredClone;
try{
  globalThis.structuredClone=function(value){trace.push('clone');return savedClone(value)};
  const written=memory.write('p',{models:[],fetchedAt:1});trace.push('after-write-call');
  written.then(()=>trace.push('write-then'));queueMicrotask(()=>trace.push('queued'));
  await written;trace.push('after-write-await');
  const read=memory.read('p');trace.push('after-read-call');await read;trace.push('after-read-await');
  add('actual-memory-async-order',trace);
}finally{globalThis.structuredClone=savedClone}
const marker={marker:'abort'};const controller=new AbortController();controller.abort(marker);
const rejected=memory.read('p',{signal:controller.signal});
try{await rejected;add('actual-memory-raw-rejection',false)}catch(error){add('actual-memory-raw-rejection',error===marker)}
for(const [name,fn]of [['ModelConfig.load',classes.ModelConfig.load],['Memory.read',classes.InMemoryCodingAgentModelsStore.prototype.read],['File.readLatest',classes.FileModelsStore.prototype.readLatest],['Runtime.getAuth',classes.ModelRuntime.prototype.getAuth],['Session.dispose',classes.AgentSessionRuntime.prototype.dispose]]){
  let rejected=false;try{Reflect.construct(fn,[])}catch(error){rejected=error instanceof TypeError}
  add('actual-async-nonconstructor-'+name,rejected);
}
globalThis.ActualSdkAsyncBrandRows=rows;
