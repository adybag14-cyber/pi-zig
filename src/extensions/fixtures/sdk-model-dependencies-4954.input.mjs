import * as fs from 'node:fs/promises';
import {join} from 'node:path';
const {InMemoryCodingAgentModelsStore:MemoryStore,FileModelsStore,ModelConfig,ModelsConfigSchema}=globalThis.ActualSdkModelDependencies;
const root=globalThis.ActualSdkModelFixtureDir;
if(typeof root!=='string'||!root)throw Error('Actual isolated fixture directory required');
const rows=[];
const add=(name,value)=>rows.push({name,value});
const caught=async(fn)=>{try{await fn();return null}catch(error){return {name:error?.name,message:error?.message,code:error?.code}}};
const methods=ctor=>Object.getOwnPropertyNames(ctor.prototype).map(name=>({name,enumerable:Object.getOwnPropertyDescriptor(ctor.prototype,name).enumerable,length:typeof ctor.prototype[name]==='function'?ctor.prototype[name].length:null}));
add('ordinary-class-metadata',{memory:{name:MemoryStore.name,length:MemoryStore.length,methods:methods(MemoryStore)},file:{name:FileModelsStore.name,length:FileModelsStore.length,methods:methods(FileModelsStore)},config:{name:ModelConfig.name,length:ModelConfig.length,methods:methods(ModelConfig),loadLength:ModelConfig.load.length,loadAsync:Object.getPrototypeOf(ModelConfig.load)===Object.getPrototypeOf(async()=>{})}});
const memory=new MemoryStore();
add('memory-instance',{keys:Object.keys(memory),ordinary:memory instanceof MemoryStore,map:memory.entries instanceof Map});
const original={fetchedAt:1,models:[{id:'one',nested:{a:1}}]};
add('memory-write-return',await memory.write('p',original));
original.models[0].nested.a=99;
const read=await memory.read('p');
add('memory-write-clone',read);
read.models[0].nested.a=88;
add('memory-read-clone',await memory.read('p'));
add('memory-read-missing',await memory.read('missing'));
add('memory-delete-return',await memory.delete('p'));
add('memory-delete-result',await memory.read('p'));
for(const method of ['read','write','delete']){
  const marker={kind:'abort',method};
  const controller=new AbortController();controller.abort(marker);
  try{await memory[method]('x',...(method==='write'?[{}]:[]),{signal:controller.signal});add('memory-abort-'+method,false)}catch(error){add('memory-abort-'+method,error===marker)}
}
{
  const events=[];
  const saved=globalThis.structuredClone;
  const entries=memory.entries;
  const raw={marker:'clone'};
  Object.defineProperty(memory,'entries',{configurable:true,get(){events.push('entries');return {get set(){events.push('set');return function(){events.push('call')}}}}});
  globalThis.structuredClone=function(){events.push('clone');throw raw};
  try{await memory.write('x',{});add('memory-write-order',false)}catch(error){add('memory-write-order',{same:error===raw,events})}
  finally{globalThis.structuredClone=saved;Object.defineProperty(memory,'entries',{configurable:true,enumerable:true,writable:true,value:entries})}
}
const storePath=join(root,'models-store.json');
const file=new FileModelsStore(storePath);
add('file-instance',{keys:Object.keys(file),ordinary:file instanceof FileModelsStore,path:file.path.endsWith('models-store.json'),readStateKeys:Object.keys(file.readState)});
add('file-empty-read',await file.read('p'));
const entry={fetchedAt:2,models:[{id:'disk',nested:{a:1}}]};
add('file-write-return',await file.write('p',entry));
entry.models[0].nested.a=90;
add('file-write-clone',await file.read('p'));
const fileValue=await file.read('p');fileValue.models[0].nested.a=80;
add('file-read-clone',await file.read('p'));
add('file-json-bytes',await fs.readFile(storePath,'utf8'));
const peer=new FileModelsStore(storePath);
add('file-shared-default-state',peer.readState===file.readState);
file.readState.revision=undefined;
const concurrentFirst=file.read('p');
const concurrentSecond=peer.read('p');
add('file-shared-reload-concurrent',{differentPromises:concurrentFirst!==concurrentSecond,values:await Promise.all([concurrentFirst,concurrentSecond])});
const custom1=new FileModelsStore(join(root,'custom.json'));
const custom2=new FileModelsStore(join(root,'custom.json'));
add('file-bounded-custom-state',custom1.readState!==custom2.readState);
await peer.write('q',{fetchedAt:3,models:[]});
add('file-peer-mutation',await file.read('q'));
add('file-delete-return',await file.delete('p'));
add('file-delete-result',await file.read('p'));
await fs.writeFile(storePath,'\uFEFF'+JSON.stringify({external:{models:[],fetchedAt:4}}));
add('file-external-bom-reload',await peer.read('external'));
await fs.writeFile(storePath,'{broken');
add('file-parse-rejection',await caught(()=>file.read('external')));
await fs.writeFile(storePath,JSON.stringify({p:{models:[],fetchedAt:5}}));
add('file-after-parse-rejection',await file.read('p'));
for(const method of ['read','write','delete']){
  const marker={kind:'file-abort',method};
  const controller=new AbortController();controller.abort(marker);
  try{await file[method]('x',...(method==='write'?[{}]:[]),{signal:controller.signal});add('file-abort-'+method,false)}catch(error){add('file-abort-'+method,error===marker)}
}
{
  const events=[];const raw={marker:'property-key'};
  const key={[Symbol.toPrimitive](){events.push('key');return 'getter-id'}};
  const saved=globalThis.structuredClone;
  globalThis.structuredClone=function(){events.push('clone');throw raw};
  try{await file.write(key,{});add('file-key-before-clone',false)}catch(error){add('file-key-before-clone',{same:error===raw,events})}
  finally{globalThis.structuredClone=saved}
}
add('file-parsed-empty',file.parse(undefined));
add('file-parsed-bom',file.parse('\uFEFF{"a":1}'));
{
  const events=[];const state={set data(value){events.push(['data',value])},set revision(value){events.push(['revision',value])}};
  file.updateReadState(state,{x:1},'r');add('file-update-getter-order',events);
}
for(const value of [undefined,null,'',false,0]){
  const config=await ModelConfig.load(value);
  add('config-empty-'+String(value),{ordinary:config instanceof ModelConfig,ids:config.getProviderIds(),error:config.getError(),keys:Object.keys(config)});
}
const missing=await ModelConfig.load(join(root,'missing.json'));
add('config-missing',{ids:missing.getProviderIds(),error:missing.getError()});
const configPath=join(root,'models.json');
const valid={providers:{custom:{name:'Custom',api:'openai-completions',baseUrl:'https://example.test/v1',models:[{id:'m',cost:{input:1,output:2,cacheRead:3,cacheWrite:4},contextWindow:2048,maxTokens:1024}],modelOverrides:{m:{cost:{input:0.5}}}}}};
await fs.writeFile(configPath,'\uFEFF// leading comment\n'+JSON.stringify(valid,null,2).replace(/\n}/,'\n,}'));
const config=await ModelConfig.load(configPath);
const provider=config.getProvider('custom');
add('config-valid',{ids:config.getProviderIds(),error:config.getError(),provider,keys:Object.keys(config),map:config.providers instanceof Map});
add('config-deep-freeze',{provider:Object.isFrozen(provider),models:Object.isFrozen(provider.models),model:Object.isFrozen(provider.models[0]),cost:Object.isFrozen(provider.models[0].cost),override:Object.isFrozen(provider.modelOverrides.m.cost)});
add('config-provider-identity',provider===config.getProvider('custom'));
const ids=config.getProviderIds();ids.push('injected');add('config-id-snapshot',config.getProviderIds());
await fs.writeFile(configPath,JSON.stringify({providers:{changed:{name:'Changed'}}}));
add('config-immutable-load',{old:config.getProviderIds(),new:(await ModelConfig.load(configPath)).getProviderIds()});
for(const [name,value]of [
  ['required',{}],['provider-type',{providers:{p:1}}],['empty-id',{providers:{p:{models:[{id:''}]}}}],
  ['negative-context',{providers:{p:{models:[{id:'m',contextWindow:-1}]}}}],
  ['radius-oauth',{providers:{p:{oauth:'other'}}}],['cost-type',{providers:{p:{modelOverrides:{m:{cost:{input:'bad'}}}}}}],
]){
  await fs.writeFile(configPath,JSON.stringify(value));
  const invalid=await ModelConfig.load(configPath);
  add('config-invalid-'+name,{ids:invalid.getProviderIds(),error:invalid.getError()?.replaceAll(configPath,'<fixture>')});
}
await fs.writeFile(configPath,'{broken');
const broken=await ModelConfig.load(configPath);
add('config-parse-error',{ids:broken.getProviderIds(),error:broken.getError()?.replaceAll(configPath,'<fixture>')});
add('config-schema',{type:ModelsConfigSchema.type,required:ModelsConfigSchema.required,properties:Object.keys(ModelsConfigSchema.properties)});
globalThis.ActualSdkModelDependencyRows=rows;
