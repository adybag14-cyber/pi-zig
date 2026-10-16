// Prepared original Map-hook controls. Run each caseId in a fresh sealed
// process/context; no expected output or replacement LRU implementation.
const {hosted,caseId}=GitAPI;
if(!['ordinary','partial_set','nested_update','undefined_delete','eviction'].includes(caseId))throw Error('Explicit fresh-context Map case required');
const source=caseId==='undefined_delete'?'https://lru-delete.test/repo':`github:lru-map-observation/${caseId}`;
const key=source+'{}',trace=[],rows=[];
const originals=Object.fromEntries(['get','set','delete','clear'].map(name=>[name,Object.getOwnPropertyDescriptor(Map.prototype,name)]));
const methods=Object.fromEntries(Object.entries(originals).map(([name,descriptor])=>[name,descriptor.value]));
let capturedMap,entered=false,nested,failed=false,allow=false;
const relevant=(map,key)=>map===capturedMap||(typeof key==='string'&&(key.includes('lru-map-observation/')||key.startsWith('https://lru-delete.test/')));
if(caseId==='undefined_delete')hosted.addHost('lru-delete',{protocols:['https:'],domain:'lru-delete.test',extract(){return allow?{user:'user',project:'repo',committish:''}:undefined}});
const marker={actual:'Map.set-after-write'};
try{
 for(const name of ['get','set','delete','clear'])Object.defineProperty(Map.prototype,name,{...originals[name],value:function(...args){
  const tracked=relevant(this,args[0]);if(tracked){capturedMap=this;trace.push({operation:name,key:args[0],index:name==='set'?args[1]:undefined})}
  if(name==='get'&&args[0]===key&&!entered&&(caseId==='nested_update'||caseId==='undefined_delete')){entered=true;allow=true;try{nested=hosted.fromUrl(source)}finally{allow=false};return undefined}
  const result=Reflect.apply(methods[name],this,args);
  if(name==='set'&&args[0]===key&&caseId==='partial_set'&&!failed){failed=true;nested=hosted.fromUrl(source);throw marker}
  return result;
 }});
 if(caseId==='ordinary'){
  const first=hosted.fromUrl(source),second=hosted.fromUrl(source);hosted.fromUrl('https://github.com/');hosted.fromUrl('https://github.com/');rows.push({name:'actual-Map-miss-hit-and-uncached-undefined',same:first===second,mapBrand:Object.prototype.toString.call(capturedMap),trace});
 }else if(caseId==='partial_set'){
  let failure;try{hosted.fromUrl(source)}catch(error){failure=error};const after=hosted.fromUrl(source),replacement=hosted.fromUrl('github:lru-map-observation/replacement'),alias=hosted.fromUrl(source);rows.push({name:'Map-set-throw-preserves-Source-partial-write-order',sameFailure:failure===marker,sameDuring:after===nested,duringProject:nested?.project,replacementProject:replacement.project,aliasProject:alias.project,aliasSame:alias===replacement,trace});
 }else if(caseId==='nested_update'){
  const outer=hosted.fromUrl(source),cached=hosted.fromUrl(source);rows.push({name:'Map-get-reentry-forced-miss-updates-existing-index',distinct:nested!==outer,cached:cached===outer,trace});
 }else if(caseId==='undefined_delete'){
  const outer=hosted.fromUrl(source);rows.push({name:'undefined-set-reentrant-last-entry-uses-Map-clear',outerUndefined:outer===undefined,nestedProject:nested?.project,trace});
 }else{
  for(let i=0;i<1000;i++)hosted.fromUrl(`github:lru-map-observation/item${i}`);
  const retained=hosted.fromUrl('github:lru-map-observation/item0');hosted.fromUrl('github:lru-map-observation/item1000');const hit=hosted.fromUrl('github:lru-map-observation/item0'),reparsed=hosted.fromUrl('github:lru-map-observation/item1');rows.push({name:'Map-fixed-index-LRU-promotion-delete-before-reuse',retained:retained===hit,reparsedProject:reparsed.project,trace});
 }
}finally{for(const name of ['get','set','delete','clear'])Object.defineProperty(Map.prototype,name,originals[name])}
globalThis.gitHostMapLifecycleRows=rows;globalThis.gitSourceHostedRows=rows;globalThis.gitSourceHostedComplete=true;
