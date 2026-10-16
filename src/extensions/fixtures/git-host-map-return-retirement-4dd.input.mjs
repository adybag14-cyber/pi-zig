// Prepared original ignored-return lifetime observation. The harness must
// supply actual job advancement and GC; neither is simulated by this input.
const {hosted,advanceJob,collectGarbage}=GitAPI;
if(typeof advanceJob!=='function'||typeof collectGarbage!=='function')throw Error('Actual job/GC capabilities required');
let clearHolder={ignored:'Map.clear'},fillHolder={ignored:'values.fill'};
const clearWeak=new WeakRef(clearHolder),fillWeak=new WeakRef(fillHolder),finalized=[];
const registry=new FinalizationRegistry(token=>finalized.push(token));registry.register(clearHolder,'clear');registry.register(fillHolder,'fill');
await advanceJob();collectGarbage(); // Retire the WeakRef-construction job first.
const source='https://lru-return-retirement.test/repo',key=source+'{}',rows=[],trace=[];
const get=Object.getOwnPropertyDescriptor(Map.prototype,'get'),clear=Object.getOwnPropertyDescriptor(Map.prototype,'clear'),fill=Object.getOwnPropertyDescriptor(Array.prototype,'fill');
let entered=false,allow=false,capturedMap,clearStarted=false,fills=0,nested;
hosted.addHost('lru-return-retirement',{protocols:['https:'],domain:'lru-return-retirement.test',extract(){return allow?{user:'user',project:'repo',committish:''}:undefined}});
try{
 Object.defineProperty(Map.prototype,'get',{...get,value:function(candidate){if(candidate===key&&!entered){entered=true;capturedMap=this;allow=true;try{nested=hosted.fromUrl(source)}finally{allow=false};return undefined}return Reflect.apply(get.value,this,arguments)}});
 Object.defineProperty(Map.prototype,'clear',{...clear,value:function(){const result=Reflect.apply(clear.value,this,arguments);if(this!==capturedMap)return result;clearStarted=true;const ignored=clearHolder;clearHolder=null;trace.push({operation:'clear'});return ignored}});
 Object.defineProperty(Array.prototype,'fill',{...fill,value:function(){
  if(!clearStarted)return Reflect.apply(fill.value,this,arguments);
  fills++;collectGarbage();trace.push({operation:`fill-${fills}`,clearAlive:clearWeak.deref()!==undefined,fillAlive:fills>1?fillWeak.deref()!==undefined:undefined});
  const result=Reflect.apply(fill.value,this,arguments);
  if(fills===1){const ignored=fillHolder;fillHolder=null;return ignored}return result;
 }});
 const outer=hosted.fromUrl(source);rows.push({name:'ignored-clear-and-fill-return-retirement',outerUndefined:outer===undefined,nestedProject:nested?.project,trace});
}finally{Object.defineProperty(Map.prototype,'get',get);Object.defineProperty(Map.prototype,'clear',clear);Object.defineProperty(Array.prototype,'fill',fill)}
await advanceJob();collectGarbage();rows.push({name:'ignored-return-post-job-weak-finalizer-observation',clearAlive:clearWeak.deref()!==undefined,fillAlive:fillWeak.deref()!==undefined,finalized:finalized.slice()});
// Finalization callback timing is recorded, never asserted by this input.
globalThis.gitHostReturnRetirementRows=rows;globalThis.gitSourceHostedRows=rows;globalThis.gitSourceHostedComplete=true;
